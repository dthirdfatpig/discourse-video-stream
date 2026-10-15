# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseVideoStream::PrepareUploadService do
  let(:service_params) do
    {
      file_name: "test-clip.mp4",
      file_size: "10485760",
      file_type: "video/mp4",
      creator_id: 1,
    }
  end

  context "when provider is cloudflare" do
    before do
      SiteSetting.video_stream_provider = "cloudflare"
      SiteSetting.video_stream_account_id = "cf-acc-123"
      SiteSetting.video_stream_api_token = "cf-token"
    end

    it "returns cloudflare upload endpoint" do
      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details]).to eq(
        provider: "cloudflare",
        endpoint: "/video-stream/upload-url.json",
      )
    end

    it "fails when credentials are missing" do
      SiteSetting.video_stream_api_token = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end
  end

  context "when provider is bunny" do
    let(:library_id) { "99999" }
    let(:api_key) { "bunny-secret-api-key" }

    before do
      SiteSetting.video_stream_provider = "bunny"
      SiteSetting.video_stream_bunny_library_id = library_id
      SiteSetting.video_stream_bunny_api_key = api_key
    end

    it "creates video on Bunny and returns client TUS credentials" do
      create_response =
        instance_double(
          Faraday::Response,
          status: 200,
          body: { "guid" => "bunny-video-uuid" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).with(
        "https://video.bunnycdn.com/library/#{library_id}/videos",
        anything,
        hash_including("AccessKey" => api_key),
      ).and_return(create_response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(context[:upload_details][:provider]).to eq("bunny")
      expect(context[:upload_details][:endpoint]).to eq("https://video.bunnycdn.com/tusupload")
      expect(context[:upload_details][:video_id]).to eq("bunny-video-uuid")
      expect(context[:upload_details][:headers]).to include(
        "LibraryId" => library_id,
        "VideoId" => "bunny-video-uuid",
      )
      expect(context[:upload_details][:headers]["AuthorizationSignature"]).to be_present
      expect(context[:upload_details][:headers]["AuthorizationExpire"]).to be_present
    end

    it "uses original file name when video_stream_keep_original_name is enabled" do
      SiteSetting.video_stream_keep_original_name = true

      create_response =
        instance_double(
          Faraday::Response,
          status: 200,
          body: { "guid" => "bunny-video-uuid" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).with(
        "https://video.bunnycdn.com/library/#{library_id}/videos",
        { title: "test-clip.mp4" }.to_json,
        anything,
      ).and_return(create_response)

      context = described_class.call(params: service_params)

      expect(context.success?).to eq(true)
      expect(Faraday).to have_received(:post).with(
        "https://video.bunnycdn.com/library/#{library_id}/videos",
        { title: "test-clip.mp4" }.to_json,
        anything,
      )
    end

    it "fails when Bunny credentials are missing" do
      SiteSetting.video_stream_bunny_library_id = ""

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("video_stream.errors.misconfigured"))
      expect(context[:status]).to eq(422)
    end

    it "fails when Bunny video creation fails" do
      create_response =
        instance_double(
          Faraday::Response,
          status: 401,
          body: { "message" => "Unauthorized" }.to_json,
          headers: {},
        )

      allow(Faraday).to receive(:post).and_return(create_response)

      context = described_class.call(params: service_params)

      expect(context.failure?).to eq(true)
      expect(context[:error]).to eq(I18n.t("video_stream.errors.upload_url"))
      expect(context[:status]).to eq(422)
    end
  end
end
