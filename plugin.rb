# frozen_string_literal: true

# name: discourse-topic-cover
# about: Adds a required, explicit cover image to Discourse topics.
# meta_topic_id: 0
# version: 0.2.1
# authors: rio
# url: https://github.com/rio/discourse-topic-cover
# required_version: 3.5.0

enabled_site_setting :topic_cover_enabled

register_asset "stylesheets/common/topic-cover.scss"

module ::DiscourseTopicCover
  PLUGIN_NAME = "discourse-topic-cover"
  UPLOAD_ID_FIELD = "topic_cover_upload_id"
  UPLOAD_URL_FIELD = "topic_cover_upload_url"
  UPLOAD_WIDTH_FIELD = "topic_cover_upload_width"
  UPLOAD_HEIGHT_FIELD = "topic_cover_upload_height"
end

require_relative "lib/discourse_topic_cover/engine"

after_initialize do
  require_relative "lib/discourse_topic_cover/upload_manager"
  require_relative "lib/discourse_topic_cover/queued_post_support"

  allow_new_queued_post_payload_attribute(:topic_opts)
  ReviewableQueuedPost.prepend(DiscourseTopicCover::ReviewableQueuedPostExtension)

  register_editable_topic_custom_field(DiscourseTopicCover::UPLOAD_ID_FIELD)
  register_topic_custom_field_type(DiscourseTopicCover::UPLOAD_ID_FIELD, :integer)
  register_topic_custom_field_type(
    DiscourseTopicCover::UPLOAD_URL_FIELD,
    :string,
    max_length: 2_000,
  )
  register_topic_custom_field_type(DiscourseTopicCover::UPLOAD_WIDTH_FIELD, :integer)
  register_topic_custom_field_type(DiscourseTopicCover::UPLOAD_HEIGHT_FIELD, :integer)

  add_preloaded_topic_list_custom_field(DiscourseTopicCover::UPLOAD_ID_FIELD)
  add_preloaded_topic_list_custom_field(DiscourseTopicCover::UPLOAD_URL_FIELD)
  add_preloaded_topic_list_custom_field(DiscourseTopicCover::UPLOAD_WIDTH_FIELD)
  add_preloaded_topic_list_custom_field(DiscourseTopicCover::UPLOAD_HEIGHT_FIELD)

  on(:after_validate_topic) do |topic, topic_creator|
    next unless topic.regular?
    next if topic_creator.opts[:skip_validations]

    custom_fields =
      topic_creator.opts.dig(:topic_opts, :custom_fields) ||
        topic_creator.opts[:custom_fields] ||
        {}
    upload_id =
      custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD] ||
        custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD.to_sym]

    if upload_id.blank?
      topic.errors.add(:base, I18n.t("discourse_topic_cover.errors.required")) if
        SiteSetting.topic_cover_required
      next
    end

    unless DiscourseTopicCover::UploadManager.valid_upload_for_user?(
             upload_id,
             topic_creator.user,
           )
      topic.errors.add(:base, I18n.t("discourse_topic_cover.errors.invalid"))
    end
  end

  on(:before_create_topic) do |topic, topic_creator|
    next unless topic.regular?

    upload_id = topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD]
    next if upload_id.blank?

    upload = DiscourseTopicCover::UploadManager.find_valid_upload(upload_id, topic_creator.user)
    if upload
      variant = DiscourseTopicCover::UploadManager.cover_variant(upload)
      topic.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD] = variant[:url]
      topic.custom_fields[DiscourseTopicCover::UPLOAD_WIDTH_FIELD] = variant[:width]
      topic.custom_fields[DiscourseTopicCover::UPLOAD_HEIGHT_FIELD] = variant[:height]
    end
  end

  on(:topic_created) do |topic|
    DiscourseTopicCover::UploadManager.sync_reference!(topic)
  end

  add_model_callback(TopicCustomField, :before_destroy) do
    if name == DiscourseTopicCover::UPLOAD_ID_FIELD
      UploadReference.where(target: self).delete_all
    end
  end

  add_model_callback(ReviewableQueuedPost, :after_save) do
    DiscourseTopicCover::QueuedPostSupport.ensure_upload_reference(self)
  end

  add_to_serializer(:topic_list_item, :topic_cover_upload_id) do
    object.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD]&.to_i
  end

  add_to_serializer(:topic_list_item, :topic_cover_url) do
    object.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD]
  end

  # Topic List Thumbnails normally derives this value from the first image in
  # the post. Prefer the explicit cover without an upload query per topic.
  add_to_serializer(:topic_list_item, :thumbnails) do
    url = object.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD]
    width = object.custom_fields[DiscourseTopicCover::UPLOAD_WIDTH_FIELD].to_i
    height = object.custom_fields[DiscourseTopicCover::UPLOAD_HEIGHT_FIELD].to_i

    if url.present? && width.positive? && height.positive?
      [
        {
          max_width: nil,
          max_height: nil,
          width: width,
          height: height,
          url: url,
        },
      ]
    else
      object.thumbnail_info(
        enqueue_if_missing: true,
        extra_sizes: theme_modifier_helper.topic_thumbnail_sizes,
      )
    end
  end

  add_to_serializer(:topic_view, :topic_cover_upload_id) do
    object.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD]&.to_i
  end

  add_to_serializer(:topic_view, :topic_cover_url) do
    object.topic.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD]
  end

  add_to_serializer(:basic_topic, :topic_cover_upload_id) do
    object.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD]&.to_i
  end

  add_to_serializer(:basic_topic, :topic_cover_url) do
    object.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD]
  end

  Discourse::Application.routes.append do
    mount DiscourseTopicCover::Engine, at: "/topic-cover"
  end
end
