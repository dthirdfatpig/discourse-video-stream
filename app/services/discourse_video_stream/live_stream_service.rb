# frozen_string_literal: true

module DiscourseVideoStream
  class LiveStreamService
    include ::Service::Base

    CF_LIVE_INPUT_PATH =
      "https://api.cloudflare.com/client/v4/accounts/%{account_id}/stream/live_inputs"
    BUNNY_LIVE_PATH =
      "https://video.bunnycdn.com/library/%{library_id}/live"

    # @!method self.call(name:)
    #   @return [Service::Base::Context]

    params { attribute :name, :string, default: "Discourse Live Stream" }

    model :live_input

    private

    def fetch_live_input(params:)
      provider = SiteSetting.video_stream_provider.presence || "cloudflare"

      if provider == "bunny"
        fetch_bunny_live_input(params)
      else
        fetch_cloudflare_live_input(params)
      end
    end

    def fetch_cloudflare_live_input(params)
      account_id = SiteSetting.video_stream_account_id.presence
      api_token = SiteSetting.video_stream_api_token.presence

      if account_id.blank? || api_token.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      url = CF_LIVE_INPUT_PATH % { account_id: account_id }

      payload = { meta: { name: params.name }, recording: { mode: "automatic" } }

      response =
        Faraday.post(
          url,
          payload.to_json,
          { "Authorization" => "Bearer #{api_token}", "Content-Type" => "application/json" },
        )

      if response.status >= 400
        log_failure(response.status, parse_body(response.body))
        context.fail!(error: I18n.t("video_stream.errors.create_live_input"), status: 422)
      end

      body = parse_body(response.body)

      unless body.dig("result", "uid")
        log_failure(response.status, body)
        context.fail!(error: I18n.t("video_stream.errors.create_live_input"), status: 422)
      end

      result = body["result"]

      {
        uid: result["uid"],
        rtmps_url: result.dig("rtmps", "url"),
        rtmps_stream_key: result.dig("rtmps", "streamKey"),
        created: result["created"],
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("video_stream.errors.create_live_input"), status: 422)
    end

    def fetch_bunny_live_input(params)
      library_id = SiteSetting.video_stream_bunny_library_id.presence
      api_key = SiteSetting.video_stream_bunny_api_key.presence

      if library_id.blank? || api_key.blank?
        context.fail!(error: I18n.t("video_stream.errors.misconfigured"), status: 422)
      end

      url = BUNNY_LIVE_PATH % { library_id: library_id }
      payload = { title: params.name }

      response =
        Faraday.post(
          url,
          payload.to_json,
          {
            "AccessKey" => api_key,
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          },
        )

      if response.status >= 400
        log_failure(response.status, parse_body(response.body))
        context.fail!(error: I18n.t("video_stream.errors.create_live_input"), status: 422)
      end

      body = parse_body(response.body)
      uid = body["id"] || body["guid"]

      if uid.blank?
        log_failure(response.status, body)
        context.fail!(error: I18n.t("video_stream.errors.create_live_input"), status: 422)
      end

      rtmp_url = body["rtmpServer"] || body["rtmpUrl"] || "rtmp://live.bunnycdn.com/live"
      stream_key = body["streamKey"] || uid

      {
        uid: uid,
        rtmps_url: rtmp_url,
        rtmps_stream_key: stream_key,
        created: body["created"] || Time.now.iso8601,
      }
    rescue JSON::ParserError, Faraday::Error => error
      log_exception(error)
      context.fail!(error: I18n.t("video_stream.errors.create_live_input"), status: 422)
    end

    def parse_body(raw_body)
      raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
    end

    def log_failure(status, body)
      Rails.logger.error("[VideoStream] Failed to create live input (status=#{status}): #{body}")
    end

    def log_exception(error)
      Rails.logger.error("[VideoStream] Live input request raised #{error.class}: #{error.message}")
    end
  end
end
