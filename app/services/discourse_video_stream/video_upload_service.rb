# frozen_string_literal: true

require "base64"

module DiscourseVideoStream
  class VideoUploadService
    include ::Service::Base

    CF_API_PATH =
      "https://api.cloudflare.com/client/v4/accounts/%{account_id}/stream?direct_user=true"
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

    private

    def fetch_upload_details(params:)
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
        )

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
      raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
    end

    def log_failure(status, body)
      Rails.logger.error("[VideoStream] Failed to fetch upload URL (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[VideoStream] Upload URL request raised #{error.class}: #{error.message}")
    end
  end
end
