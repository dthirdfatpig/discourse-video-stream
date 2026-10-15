# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseVideoStream::VideoStreamController do
  fab!(:user)

  before do
    SiteSetting.video_stream_enabled = true
    SiteSetting.video_stream_account_id = "abc123"
    SiteSetting.video_stream_api_token = "token"
  end

  describe "POST /video-stream/upload-url" do
    it "requires login" do
      post "/video-stream/upload-url.json"

      expect(response.status).to eq(403)
    end

    it "returns 404 when the feature is disabled" do
      SiteSetting.video_stream_enabled = false

      sign_in(user)
      post "/video-stream/upload-url.json"

      expect(response.status).to eq(404)
    end

    it "returns upload headers when the service succeeds" do
      context =
        Service::Base::Context.new(
          upload_details: {
            upload_url: "https://example.com",
            stream_media_id: "123",
            tus_resumable: "1.0.0",
          },
        )
      allow(DiscourseVideoStream::VideoUploadService).to receive(:call).and_return(context)

      sign_in(user)
      post "/video-stream/upload-url.json",
           headers: {
             "Upload-Length" => "1024",
             "Upload-Metadata" => "name ZmlsZS5tcDQ=",
             "Tus-Resumable" => "1.0.0",
           }

      expect(response.status).to eq(201)
      expect(response.headers["Location"]).to eq("https://example.com")
      expect(response.headers["stream-media-id"]).to eq("123")
      expect(DiscourseVideoStream::VideoUploadService).to have_received(:call).with(
        satisfy do |args|
          expect(args[:params]).to include(
            upload_length: "1024",
            upload_metadata: "name ZmlsZS5tcDQ=",
            tus_resumable: "1.0.0",
            creator_id: user.id,
          )

          true
        end,
      )
    end

    it "renders an error payload when the service fails" do
      failure_context = Service::Base::Context.new
      failure_context.fail(error: "nope", status: 422)
      allow(DiscourseVideoStream::VideoUploadService).to receive(:call).and_return(failure_context)

      sign_in(user)
      post "/video-stream/upload-url.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq("nope")
      expect(DiscourseVideoStream::VideoUploadService).to have_received(:call)
    end
  end

  describe "POST /video-stream/prepare-upload" do
    it "requires login" do
      post "/video-stream/prepare-upload.json"

      expect(response.status).to eq(403)
    end

    it "returns 404 when the feature is disabled" do
      SiteSetting.video_stream_enabled = false

      sign_in(user)
      post "/video-stream/prepare-upload.json"

      expect(response.status).to eq(404)
    end

    it "returns upload details when PrepareUploadService succeeds" do
      context =
        Service::Base::Context.new(
          upload_details: {
            provider: "bunny",
            endpoint: "https://video.bunnycdn.com/tusupload",
            video_id: "guid-123",
            headers: {
              "LibraryId" => "123",
              "VideoId" => "guid-123",
            },
          },
        )
      allow(DiscourseVideoStream::PrepareUploadService).to receive(:call).and_return(context)

      sign_in(user)
      post "/video-stream/prepare-upload.json",
           params: {
             file_name: "sample.mp4",
             file_size: 1024,
             file_type: "video/mp4",
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["provider"]).to eq("bunny")
      expect(response.parsed_body["video_id"]).to eq("guid-123")
      expect(DiscourseVideoStream::PrepareUploadService).to have_received(:call).with(
        satisfy do |args|
          expect(args[:params]).to include(
            file_name: "sample.mp4",
            file_size: "1024",
            file_type: "video/mp4",
            creator_id: user.id,
          )
          true
        end,
      )
    end

    it "renders error payload when PrepareUploadService fails" do
      failure_context = Service::Base::Context.new
      failure_context.fail(error: "cannot prepare", status: 422)
      allow(DiscourseVideoStream::PrepareUploadService).to receive(:call).and_return(failure_context)

      sign_in(user)
      post "/video-stream/prepare-upload.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq("cannot prepare")
    end
  end
end
