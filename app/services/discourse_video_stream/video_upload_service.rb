# frozen_string_literal: true

require "base64"
require "openssl"

module DiscourseVideoStream
  class VideoUploadService
    include ::Service::Base

    CF_API_PATH =
      "https://api.cloudflare.com/client/v4/accounts/%{account_id}/stream?direct_user=true"
    BUNNY_API_HOST = "https://video.bunnycdn.com"
    DEFAULT_MAX_DURATION_SECONDS = 300
    DEFAULT_TUS_VERSION = "1.0.0"

    # @!method self.call(upload_length:, upload_metadata:, upload_defer_length:, tus_resumable:, creator_id:)
    #   @return [Service::Base::Context]

    params do
      attribute :upload_length, :string
      attribute :upload_metadata, :string
      attribute :upload_defer_length, :string
      attribute :tus_resumable, :string, default: DEFAULT_TUS_VERSION
      attribute :creator_id, :integer

      validate :length_or_deferred_length_present

      private

      def length_or_deferred_length_present
        errors.add(:upload_length, :blank) if upload_length.blank? && upload_defer_length.blank?
      end
    end

    model :upload_details

    FARADAY_TIMEOUT = 15
    FARADAY_OPEN_TIMEOUT = 5

    private

    def fetch_upload_details(params:)
      provider = SiteSetting.video_stream_provider.presence || "cloudflare"

      if provider == "bunny"
        fetch_bunny_upload_details(params)
      else
        fetch_cloudflare_upload_details(params)
      end
    end

    def fetch_cloudflare_upload_details(params)
      account_id = SiteSetting.video_stream_account_id.presence
      api_token = SiteSetting.video_stream_api_token.presence

      if account_id.blank? || api_token.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      response =
        Faraday.post(
          CF_API_PATH % { account_id: account_id },
          nil,
          request_headers(api_token, params),
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if response.status >= 400
        log_failure(response.status, parse_body(response.body))
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      upload_url = response.headers["Location"].presence

      if upload_url.blank?
        log_failure(response.status, parse_body(response.body))
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      {
        upload_url: upload_url,
        stream_media_id: response.headers["stream-media-id"],
        tus_resumable: response.headers["tus-resumable"].presence || params.tus_resumable,
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
    end

    def fetch_bunny_upload_details(params)
      library_id = SiteSetting.video_stream_bunny_library_id.presence
      api_key = SiteSetting.video_stream_bunny_api_key.presence

      if library_id.blank? || api_key.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      metadata = parse_metadata(params.upload_metadata)
      title = extract_video_title(metadata)

      create_response =
        Faraday.post(
          "#{BUNNY_API_HOST}/library/#{library_id}/videos",
          { title: title }.to_json,
          {
            "AccessKey" => api_key,
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          },
        ) do |req|
          req.options.timeout = FARADAY_TIMEOUT
          req.options.open_timeout = FARADAY_OPEN_TIMEOUT
        end

      if create_response.status >= 400
        log_failure(create_response.status, parse_body(create_response.body))
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      body = parse_body(create_response.body)
      video_id = body["guid"].presence

      if video_id.blank?
        log_failure(create_response.status, body)
        context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
      end

      expires = (Time.now + 24.hours).to_i
      signature_data = "#{library_id}#{api_key}#{expires}#{video_id}"
      signature = OpenSSL::Digest::SHA256.hexdigest(signature_data)

      {
        upload_url: "#{BUNNY_API_HOST}/tusupload",
        stream_media_id: video_id,
        tus_resumable: params.tus_resumable.presence || DEFAULT_TUS_VERSION,
        extra_headers: {
          "AuthorizationSignature" => signature,
          "AuthorizationExpire" => expires.to_s,
          "LibraryId" => library_id.to_s,
          "VideoId" => video_id,
        },
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("video_stream.errors.upload_url"), status: 422)
    end

    def extract_video_title(metadata)
      if SiteSetting.video_stream_keep_original_name
        encoded_name = metadata["name"] || metadata["filename"]
        if encoded_name.present?
          begin
            decoded = Base64.strict_decode64(encoded_name)
            sanitized = decoded.to_s.gsub(/[\x00-\x1f]/, "").strip
            return sanitized.truncate(255) if sanitized.present?
          rescue ArgumentError
            sanitized = encoded_name.to_s.gsub(/[\x00-\x1f]/, "").strip
            return sanitized.truncate(255) if sanitized.present?
          end
        end
      end

      "Discourse Video - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    end

    def request_headers(api_token, params)
      headers = {
        "Authorization" => "Bearer #{api_token}",
        "Tus-Resumable" => params.tus_resumable.presence || DEFAULT_TUS_VERSION,
        "Upload-Metadata" => build_upload_metadata(params.upload_metadata),
      }

      headers["Upload-Length"] = params.upload_length if params.upload_length.present?
      headers[
        "Upload-Defer-Length"
      ] = params.upload_defer_length if params.upload_defer_length.present?
      headers["Upload-Creator"] = params.creator_id.to_s if params.creator_id.present?

      headers
    end

    def build_upload_metadata(raw_metadata)
      metadata = parse_metadata(raw_metadata)

      unless metadata.key?("maxDurationSeconds")
        max_duration = SiteSetting.video_stream_max_duration.presence || DEFAULT_MAX_DURATION_SECONDS
        metadata["maxDurationSeconds"] = Base64.strict_encode64(max_duration.to_s)
      end

      if SiteSetting.video_stream_keep_original_name && metadata.key?("filename") && !metadata.key?("name")
        metadata["name"] = metadata["filename"]
      end

      metadata.map { |key, value| value.present? ? "#{key} #{value}" : key }.join(",")
    end

    def parse_metadata(raw_metadata)
      return {} if raw_metadata.blank?

      raw_metadata
        .split(",")
        .each_with_object({}) do |pair, hash|
          key, value = pair.strip.split(" ", 2)
          next if key.blank?

          hash[key] = value
        end
    end

    def parse_body(raw_body)
      return {} if raw_body.blank?
      return raw_body if raw_body.is_a?(Hash) || raw_body.is_a?(Array)

      JSON.parse(raw_body)
    rescue JSON::ParserError
      { "raw" => raw_body.to_s.truncate(500) }
    end

    def log_failure(status, body)
      Rails.logger.error("[VideoStream] Failed to fetch upload URL (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[VideoStream] Upload URL request raised #{error.class}: #{error.message}")
    end
  end
end
