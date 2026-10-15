# frozen_string_literal: true

require_dependency "application_controller"

module DiscourseVideoStream
  class VideoStreamController < ::ApplicationController
    requires_plugin DiscourseVideoStream::PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled
    before_action :ensure_can_upload_to_stream

    def create_live_stream
      context = LiveStreamService.call(params: { name: params[:name] })

      if context.failure?
        render_json_error(
          context[:error] || I18n.t("video_stream.errors.create_live_input"),
          status: context[:status] || 422,
        )
        return
      end

      render json: context[:live_input]
    end

    def prepare_upload
      context = PrepareUploadService.call(params: prepare_upload_params)

      if context.failure?
        render_json_error(
          context[:error] || I18n.t("video_stream.errors.upload_url"),
          status: context[:status] || 422,
        )
        return
      end

      render json: context[:upload_details]
    end

    def upload_url
      context = VideoUploadService.call(params: upload_request_headers)

      if context.failure?
        render_json_error(
          context[:error] || I18n.t("video_stream.errors.upload_url"),
          status: context[:status] || 422,
        )
        return
      end

      set_tus_response_headers(context[:upload_details])
      head :created
    end

    private

    def prepare_upload_params
      {
        file_name: params[:file_name] || params[:title],
        file_size: params[:file_size],
        file_type: params[:file_type],
        creator_id: current_user&.id,
      }
    end

    def upload_request_headers
      {
        upload_length: request.headers["Upload-Length"],
        upload_defer_length: request.headers["Upload-Defer-Length"],
        upload_metadata: request.headers["Upload-Metadata"],
        tus_resumable: request.headers["Tus-Resumable"],
        creator_id: current_user&.id,
      }
    end

    def ensure_feature_enabled
      raise Discourse::NotFound unless SiteSetting.video_stream_enabled
    end

    def ensure_can_upload_to_stream
      raise Discourse::InvalidAccess unless guardian.can_upload_external?
    end

    def set_tus_response_headers(upload_details)
      response.set_header("Location", upload_details[:upload_url])
      response.set_header("Tus-Resumable", upload_details[:tus_resumable])

      if upload_details[:stream_media_id].present?
        response.set_header("stream-media-id", upload_details[:stream_media_id])
      end

      if upload_details[:extra_headers].is_a?(Hash)
        upload_details[:extra_headers].each do |k, v|
          response.set_header(k.to_s, v.to_s)
        end
      end

      expose_headers = %w[
        Location
        Tus-Resumable
        stream-media-id
        AuthorizationSignature
        AuthorizationExpire
        LibraryId
        VideoId
      ].join(", ")
      response.set_header("Access-Control-Expose-Headers", expose_headers)
    end
  end
end
