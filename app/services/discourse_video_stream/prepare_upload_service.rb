# frozen_string_literal: true

require "openssl"

module DiscourseVideoStream
  class PrepareUploadService
    include ::Service::Base

    BUNNY_API_HOST = "https://video.bunnycdn.com"

    params do
      attribute :file_name, :string
      attribute :file_size, :string
      attribute :file_type, :string
      attribute :creator_id, :integer
    end

    model :upload_details

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

      {
        provider: "cloudflare",
        endpoint: "/video-stream/upload-url.json",
      }
    end

    def fetch_bunny_upload_details(params)
      library_id = SiteSetting.video_stream_bunny_library_id.presence
      api_key = SiteSetting.video_stream_bunny_api_key.presence

      if library_id.blank? || api_key.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      title = extract_video_title(params.file_name)

      create_response =
        Faraday.post(
          "#{BUNNY_API_HOST}/library/#{library_id}/videos",
          { title: title }.to_json,
          {
            "AccessKey" => api_key,
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          },
        )

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
        provider: "bunny",
        endpoint: "#{BUNNY_API_HOST}/tusupload",
        video_id: video_id,
        headers: {
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

    def extract_video_title(file_name)
      if SiteSetting.video_stream_keep_original_name && file_name.present?
        return file_name
      end

      "Discourse Video - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    end

    def parse_body(raw_body)
      raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
    end

    def log_failure(status, body)
      Rails.logger.error("[VideoStream] Failed to prepare upload (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[VideoStream] Prepare upload request raised #{error.class}: #{error.message}")
    end
  end
end
