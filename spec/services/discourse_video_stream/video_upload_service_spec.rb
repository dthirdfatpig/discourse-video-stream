# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseVideoStream::VideoUploadService do
  let(:account_id) { "abc123" }
  let(:api_token) { "shhh" }
  let(:service_params) do
    {
      upload_length: "10485760",
      upload_metadata: "name ZmlsZS5tcDQ=",
      tus_resumable: "1.0.0",
      creator_id: 1,
    }
  end

  before do
    SiteSetting.video_stream_account_id = account_id
    SiteSetting.video_stream_api_token = api_token
  end

  describe ".call" do
    it "fails when required credentials are missing" do
      SiteSetting.video_stream_api_token = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end

    it "returns upload details when Cloudflare succeeds" do
      SiteSetting.video_stream_max_duration = 600

      headers = {
        "Location" => "https://upload.videodelivery.net/tus/abc123",
        "stream-media-id" => "abc123",
        "tus-resumable" => "1.0.0",
      }
      response = instance_double(Faraday::Response, status: 201, body: nil, headers: headers)
      allow(Faraday).to receive(:post).and_return(response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details]).to include(
        upload_url: "https://upload.videodelivery.net/tus/abc123",
        stream_media_id: "abc123",
        tus_resumable: "1.0.0",
      )
      expect(Faraday).to have_received(:post).with(
        format(described_class::CF_API_PATH, account_id: account_id),
        nil,
        hash_including(
          "Authorization" => "Bearer #{api_token}",
          "Upload-Length" => service_params[:upload_length],
          "Upload-Metadata" => include(Base64.strict_encode64("600")),
        ),
      )
    end

    it "maps filename to name when video_stream_keep_original_name is enabled" do
      SiteSetting.video_stream_keep_original_name = true

      headers = {
        "Location" => "https://upload.videodelivery.net/tus/abc123",
        "stream-media-id" => "abc123",
        "tus-resumable" => "1.0.0",
      }
      response = instance_double(Faraday::Response, status: 201, body: nil, headers: headers)
      allow(Faraday).to receive(:post).and_return(response)

      params = service_params.merge(upload_metadata: "filename ZmlsZS5tcDQ=")
      context = described_class.call(params: params)

      expect(context.success?).to eq(true)
      expect(Faraday).to have_received(:post).with(
        format(described_class::CF_API_PATH, account_id: account_id),
        nil,
        hash_including(
          "Upload-Metadata" => include("name ZmlsZS5tcDQ="),
        ),
      )
    end

    it "fails when Cloudflare returns an error" do
      response =
        instance_double(
          Faraday::Response,
          status: 500,
          body: { "success" => false }.to_json,
          headers: {},
        )
      allow(Faraday).to receive(:post).and_return(response)

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("video_stream.errors.upload_url"))
      expect(Faraday).to have_received(:post)
    end
  end
end
