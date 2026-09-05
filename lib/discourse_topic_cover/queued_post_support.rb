# frozen_string_literal: true

module ::DiscourseTopicCover
  module QueuedPostSupport
    def self.cover_upload_id(payload)
      topic_opts = payload&.[]("topic_opts") || payload&.[](:topic_opts)
      return if !topic_opts.respond_to?(:[])

      custom_fields = topic_opts["custom_fields"] || topic_opts[:custom_fields]
      return if !custom_fields.respond_to?(:[])

      custom_fields[UPLOAD_ID_FIELD] || custom_fields[UPLOAD_ID_FIELD.to_sym]
    end

    def self.normalize_create_options(options)
      topic_opts = options[:topic_opts]
      return options unless topic_opts.respond_to?(:symbolize_keys)

      normalized_topic_opts = topic_opts.symbolize_keys
      custom_fields = normalized_topic_opts[:custom_fields]
      if custom_fields.respond_to?(:stringify_keys)
        normalized_topic_opts[:custom_fields] = custom_fields.stringify_keys
      end
      options[:topic_opts] = normalized_topic_opts
      options
    end

    def self.ensure_upload_reference(reviewable)
      upload_id = cover_upload_id(reviewable.payload)
      return if upload_id.blank?

      UploadReference.create_or_find_by!(
        upload_id: upload_id.to_i,
        target_type: reviewable.class.to_s,
        target_id: reviewable.id,
      )
    end
  end

  module ReviewableQueuedPostExtension
    def create_options
      DiscourseTopicCover::QueuedPostSupport.normalize_create_options(super)
    end
  end
end
