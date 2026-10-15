# frozen_string_literal: true

DiscourseVideoStream::Engine.routes.draw do
  post "/video-stream/upload-url" => "video_stream#upload_url"
  post "/video-stream/prepare-upload" => "video_stream#prepare_upload"
  post "/video-stream/create-live-stream" => "video_stream#create_live_stream"
end

Discourse::Application.routes.draw { mount ::DiscourseVideoStream::Engine, at: "/" }
