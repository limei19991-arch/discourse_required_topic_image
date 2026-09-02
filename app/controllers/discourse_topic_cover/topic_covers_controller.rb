# frozen_string_literal: true

module DiscourseTopicCover
  class TopicCoversController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in

    def update
      params.require(%i[topic_id upload_id])

      topic = Topic.find(params[:topic_id].to_i)
      guardian.ensure_can_edit!(topic)
      raise Discourse::InvalidParameters.new(:topic_id) unless topic.regular?

      upload = UploadManager.find_valid_upload(params[:upload_id], current_user)
      raise Discourse::InvalidParameters.new(:upload_id) if upload.blank?

      UploadManager.assign!(topic: topic, upload: upload, user: current_user)
      topic.reload

      render json: {
               success: true,
               topic_cover_upload_id: upload.id,
               topic_cover_url: topic.custom_fields[UPLOAD_URL_FIELD],
             }
    end
  end
end
