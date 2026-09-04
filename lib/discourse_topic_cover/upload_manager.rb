# frozen_string_literal: true

module DiscourseTopicCover
  class UploadManager
    def self.find_valid_upload(upload_id, user)
      return if upload_id.blank? || user.blank?

      normalized_id = Integer(upload_id, exception: false)
      return if normalized_id.blank? || normalized_id <= 0

      upload = Upload.find_by(id: normalized_id)
      return if upload.blank?
      return unless FileHelper.is_supported_image?(upload.original_filename)

      # Discourse deduplicates uploads by SHA1. When another user uploads the
      # same image, the Upload keeps its original user_id and Discourse records
      # the new owner in user_uploads instead.
      owned_by_user =
        upload.user_id == user.id || UserUpload.exists?(user_id: user.id, upload_id: upload.id)
      return unless user.staff? || owned_by_user

      return if upload.width.to_i < SiteSetting.topic_cover_min_width
      return if upload.height.to_i < SiteSetting.topic_cover_min_height

      upload
    end

    def self.valid_upload_for_user?(upload_id, user)
      find_valid_upload(upload_id, user).present?
    end

    def self.assign!(topic:, upload:, user:)
      raise Discourse::InvalidAccess if topic.blank? || upload.blank?
      raise Discourse::InvalidAccess unless valid_upload_for_user?(upload.id, user)

      variant = cover_variant(upload)
      topic.custom_fields[UPLOAD_ID_FIELD] = upload.id
      topic.custom_fields[UPLOAD_URL_FIELD] = variant[:url]
      topic.custom_fields[UPLOAD_WIDTH_FIELD] = variant[:width]
      topic.custom_fields[UPLOAD_HEIGHT_FIELD] = variant[:height]
      topic.save_custom_fields
      sync_reference!(topic)
    end

    def self.cover_variant(upload)
      width,
        height =
          ImageSizer.resize(
            upload.width,
            upload.height,
            {
              max_width: SiteSetting.topic_cover_max_width,
              max_height: SiteSetting.topic_cover_max_height,
            },
          )

      optimized =
        OptimizedImage.create_for(
          upload,
          width,
          height,
          format: "webp",
          quality: SiteSetting.topic_cover_image_quality,
        )
      image = optimized || upload

      { url: image.url, width: image.width, height: image.height }
    rescue StandardError => error
      Rails.logger.warn("[discourse-topic-cover] Cover optimization failed: #{error.message}")
      { url: upload.url, width: upload.width, height: upload.height }
    end

    def self.sync_reference!(topic)
      upload_id = topic.custom_fields[UPLOAD_ID_FIELD]
      return if upload_id.blank?

      field = TopicCustomField.find_by(topic_id: topic.id, name: UPLOAD_ID_FIELD)
      return if field.blank?

      UploadReference.ensure_exist!(upload_ids: [upload_id.to_i], target: field)
    end
  end
end
