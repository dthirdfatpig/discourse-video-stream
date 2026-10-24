# frozen_string_literal: true

# name: discourse-video-stream
# about: Integrates Cloudflare and Bunny.net Video Stream for video uploads and playback in Discourse.
# meta_topic_id: TODO
# version: 0.0.15
# authors: dthirdfatpig
# url: https://github.com/dthirdfatpig/discourse-video-stream
# required_version: 2.7.0

enabled_site_setting :video_stream_enabled

# Cloudflare Stream API settings
register_asset "stylesheets/common/video-stream.scss"

module ::DiscourseVideoStream
  PLUGIN_NAME = "discourse-video-stream"
end

require_relative "lib/discourse_video_stream/engine"

def humanized_name
  "Bunny.net and Cloudflare Video Stream"
end

after_initialize do
  register_svg_icon("video")
  register_svg_icon("tower-broadcast")
end
