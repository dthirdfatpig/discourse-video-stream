# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseVideoStream::LiveStreamService do
  subject(:result) { described_class.call(params: params) }

  let(:params) { { name: "Test Live Stream" } }
  let(:account_id) { "test_account_123" }
  let(:api_token) { "test_token_xyz" }

  before do
    SiteSetting.video_stream_account_id = account_id
    SiteSetting.video_stream_api_token = api_token
  end

  describe "#call" do
    context "when successful" do
      let(:cloudflare_response) do
        {
          result: {
            uid: "live_input_123",
            rtmps: {
              url: "rtmps://live.cloudflare.com:443/live/",
              streamKey: "test_stream_key_abc123",
            },
            created: "2024-01-01T00:00:00.000000Z",
            meta: {
              name: "Test Live Stream",
            },
          },
        }
      end

      before do
        stub_request(
          :post,
          "https://api.cloudflare.com/client/v4/accounts/#{account_id}/stream/live_inputs",
        ).with(
          headers: {
            "Authorization" => "Bearer #{api_token}",
            "Content-Type" => "application/json",
          },
          body: { meta: { name: "Test Live Stream" }, recording: { mode: "automatic" } }.to_json,
        ).to_return(
          status: 200,
          body: cloudflare_response.to_json,
          headers: {
            "Content-Type" => "application/json",
          },
        )
      end

      it "succeeds" do
        expect(result).to be_success
      end

      it "returns live input details" do
        expect(result[:live_input]).to include(
          uid: "live_input_123",
          rtmps_url: "rtmps://live.cloudflare.com:443/live/",
          rtmps_stream_key: "test_stream_key_abc123",
          created: "2024-01-01T00:00:00.000000Z",
        )
      end
    end

    context "when account ID is missing" do
      before { SiteSetting.video_stream_account_id = "" }

      it "fails with misconfigured error" do
        expect(result).to be_failure
        expect(result[:error]).to eq(I18n.t("video_stream.errors.misconfigured"))
        expect(result[:status]).to eq(422)
      end
    end

    context "when API token is missing" do
      before { SiteSetting.video_stream_api_token = "" }

      it "fails with misconfigured error" do
        expect(result).to be_failure
        expect(result[:error]).to eq(I18n.t("video_stream.errors.misconfigured"))
        expect(result[:status]).to eq(422)
      end
    end

    context "when Cloudflare API returns error" do
      before do
        stub_request(
          :post,
          "https://api.cloudflare.com/client/v4/accounts/#{account_id}/stream/live_inputs",
        ).to_return(status: 500, body: { errors: [{ message: "Internal server error" }] }.to_json)
      end

      it "fails with create error" do
        expect(result).to be_failure
        expect(result[:error]).to eq(I18n.t("video_stream.errors.create_live_input"))
        expect(result[:status]).to eq(422)
      end
    end

    context "when Cloudflare API response is missing uid" do
      before do
        stub_request(
          :post,
          "https://api.cloudflare.com/client/v4/accounts/#{account_id}/stream/live_inputs",
        ).to_return(status: 200, body: { result: {} }.to_json)
      end

      it "fails with create error" do
        expect(result).to be_failure
        expect(result[:error]).to eq(I18n.t("video_stream.errors.create_live_input"))
        expect(result[:status]).to eq(422)
      end
    end

    context "when network error occurs" do
      before do
        stub_request(
          :post,
          "https://api.cloudflare.com/client/v4/accounts/#{account_id}/stream/live_inputs",
        ).to_raise(Faraday::ConnectionFailed.new("Connection failed"))
      end

      it "fails with create error" do
        expect(result).to be_failure
        expect(result[:error]).to eq(I18n.t("video_stream.errors.create_live_input"))
        expect(result[:status]).to eq(422)
      end
    end

    context "when provider is bunny" do
      let(:library_id) { "bunny_lib_999" }
      let(:api_key) { "bunny_secret_key" }
      let(:bunny_response) do
        {
          id: "bunny_live_456",
          streamKey: "bunny_key_xyz",
          rtmpServer: "rtmp://live.bunnycdn.com/live",
          created: "2024-01-01T00:00:00.000000Z",
        }
      end

      before do
        SiteSetting.video_stream_provider = "bunny"
        SiteSetting.video_stream_bunny_library_id = library_id
        SiteSetting.video_stream_bunny_api_key = api_key
      end

      it "creates live stream via Bunny API" do
        stub_request(
          :post,
          "https://video.bunnycdn.com/library/#{library_id}/live",
        ).with(
          headers: {
            "AccessKey" => api_key,
            "Content-Type" => "application/json",
          },
          body: { title: "Test Live Stream" }.to_json,
        ).to_return(
          status: 200,
          body: bunny_response.to_json,
          headers: { "Content-Type" => "application/json" },
        )

        expect(result).to be_success
        expect(result[:live_input]).to include(
          uid: "bunny_live_456",
          rtmps_url: "rtmp://live.bunnycdn.com/live",
          rtmps_stream_key: "bunny_key_xyz",
        )
      end

      it "fails when Bunny library ID is missing" do
        SiteSetting.video_stream_bunny_library_id = ""

        expect(result).to be_failure
        expect(result[:error]).to eq(I18n.t("video_stream.errors.misconfigured"))
        expect(result[:status]).to eq(422)
      end
    end
  end
end
