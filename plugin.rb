# frozen_string_literal: true

# name: discourse-video-stream
# about: Integrates Cloudflare Stream for video uploads and playback in Discourse
# meta_topic_id: TODO
# version: 0.0.14
# authors: Your Name
# url: https://github.com/yourusername/discourse-video-stream
# required_version: 2.7.0

enabled_site_setting :video_stream_enabled

# Cloudflare Stream API settings
register_asset "stylesheets/common/video-stream.scss"

module ::DiscourseVideoStream
  PLUGIN_NAME = "discourse-video-stream"
end

require_relative "lib/discourse_video_stream/engine"

after_initialize do
  register_svg_icon("video")
  register_svg_icon("tower-broadcast")
end
