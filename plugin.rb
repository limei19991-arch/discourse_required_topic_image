# frozen_string_literal: true

# name: discourse-topic-cover
# about: Adds a required, explicit cover image to Discourse topics.
# meta_topic_id: 0
# version: 0.3.0
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

  # A queued post's payload is stored as JSON, so nested keys come back as
  # strings once the reviewable is reloaded from the database. PostCreator
  # merges `topic_opts` into the creator options and TopicCreator reads
  # `opts[:custom_fields]` with a symbol key, so without this conversion the
  # custom fields (including the cover upload id) are silently dropped when
  # a queued post is approved.
  module PayloadCompat
    def create_options
      result = super

      topic_opts = result[:topic_opts]
      if topic_opts.is_a?(Hash) && topic_opts.key?("custom_fields")
        topic_opts[:custom_fields] = topic_opts.delete("custom_fields")
      end

      result
    end
  end
end

require_relative "lib/discourse_topic_cover/engine"

after_initialize do
  require_relative "lib/discourse_topic_cover/upload_manager"

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
    else
      # The upload may have been removed while the post waited in the review
      # queue, or validations were skipped (queued post approval). Never
      # persist a cover the user does not own.
      topic.custom_fields.delete(DiscourseTopicCover::UPLOAD_ID_FIELD)
    end
  end

  on(:topic_created) do |topic|
    DiscourseTopicCover::UploadManager.sync_reference!(topic)
  end

  # -- Review queue support --------------------------------------------------
  #
  # New members can have their first post queued for review (fast typers,
  # approval thresholds, watched words, ...). The queue only round-trips
  # payload attributes that were explicitly registered, so allow `topic_opts`
  # (which carries the editable topic custom fields, including the cover
  # upload id) to survive: create request -> reviewable payload -> approved
  # topic. AI checks, spam detection and fast-post detection are untouched.
  NewPostManager.add_plugin_payload_attribute(:topic_opts)
  ReviewableQueuedPost.prepend(DiscourseTopicCover::PayloadCompat)

  # While the post waits in the queue, reference the cover upload from the
  # reviewable so it is not swept up by the orphaned upload cleanup, the same
  # way core references uploads embedded in the queued post's raw text.
  on(:queued_post_created) do |reviewable|
    next unless reviewable.is_a?(ReviewableQueuedPost)

    payload = reviewable.payload || {}
    topic_opts = payload[:topic_opts] || payload["topic_opts"] || {}
    custom_fields = topic_opts[:custom_fields] || topic_opts["custom_fields"] || {}
    upload_id =
      custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD] ||
        custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD.to_sym]
    next if upload_id.blank?

    upload_id = Integer(upload_id, exception: false)
    next if upload_id.blank? || upload_id <= 0

    UploadReference.ensure_exist!(upload_ids: [upload_id], target: reviewable)
  end

  # Approving a queued post creates the topic with `skip_events: true`, so
  # the regular `topic_created` hook above never fires. Sync the durable
  # upload reference from the approval event instead.
  on(:approved_post) do |_reviewable, post|
    next if post.blank? || !post.is_first_post?

    DiscourseTopicCover::UploadManager.sync_reference!(post.topic)
  end

  add_model_callback(TopicCustomField, :before_destroy) do
    if name == DiscourseTopicCover::UPLOAD_ID_FIELD
      UploadReference.where(target: self).delete_all
    end
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
