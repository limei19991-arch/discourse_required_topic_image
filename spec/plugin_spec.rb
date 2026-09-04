# frozen_string_literal: true

RSpec.describe "Discourse Topic Cover" do
  fab!(:user)
  fab!(:admin)
  fab!(:upload) do
    Fabricate(
      :upload,
      user: user,
      original_filename: "cover.png",
      extension: "png",
      width: 1200,
      height: 675,
    )
  end

  before do
    SiteSetting.topic_cover_enabled = true
    SiteSetting.topic_cover_required = true
  end

  it "rejects a regular topic without a cover" do
    post = PostCreator.create(user, title: "A topic without a cover", raw: "Topic body text")

    expect(post.errors.full_messages.join(" ")).to include(
      I18n.t("discourse_topic_cover.errors.required"),
    )
  end

  it "stores the cover and creates a durable upload reference" do
    post =
      PostCreator.create(
        user,
        title: "A topic with a cover",
        raw: "Topic body text",
        topic_opts: {
          custom_fields: {
            DiscourseTopicCover::UPLOAD_ID_FIELD => upload.id,
          },
        },
      )

    expect(post.errors).to be_empty
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD]).to eq(upload.url)
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_WIDTH_FIELD].to_i).to eq(upload.width)
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_HEIGHT_FIELD].to_i).to eq(upload.height)

    field =
      TopicCustomField.find_by!(
        topic_id: post.topic_id,
        name: DiscourseTopicCover::UPLOAD_ID_FIELD,
      )
    expect(UploadReference.exists?(target: field, upload: upload)).to eq(true)
  end

  it "rejects an upload owned by another user" do
    other_user = Fabricate(:user)
    post =
      PostCreator.create(
        other_user,
        title: "A topic using another user's cover",
        raw: "Topic body text",
        topic_opts: {
          custom_fields: {
            DiscourseTopicCover::UPLOAD_ID_FIELD => upload.id,
          },
        },
      )

    expect(post.errors.full_messages.join(" ")).to include(
      I18n.t("discourse_topic_cover.errors.invalid"),
    )
  end

  it "accepts a deduplicated upload associated through UserUpload" do
    other_user = Fabricate(:user)
    UserUpload.create!(user: other_user, upload: upload)

    post =
      PostCreator.create(
        other_user,
        title: "A topic with a deduplicated cover",
        raw: "Topic body text",
        topic_opts: {
          custom_fields: {
            DiscourseTopicCover::UPLOAD_ID_FIELD => upload.id,
          },
        },
      )

    expect(post.errors).to be_empty
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
  end

  describe "review queue" do
    before { SiteSetting.approve_post_count = 1 }

    # Mirrors PostsController#create: the client sends
    # topic_custom_fields[topic_cover_upload_id], and the controller wraps the
    # editable topic custom fields in topic_opts. Fast typing args simulate a
    # new member pasting and submitting their very first post.
    def submit_first_topic(posting_user, cover_upload_id: nil)
      args = {
        title: "A first topic that will be reviewed",
        raw: "This is the body of the very first topic from a new member.",
        first_post_checks: true,
        typing_duration_msecs: 100,
        composer_open_duration_msecs: 500,
      }

      if cover_upload_id
        args[:topic_opts] = {
          custom_fields: { DiscourseTopicCover::UPLOAD_ID_FIELD => cover_upload_id },
        }
      end

      NewPostManager.new(posting_user, args).perform
    end

    it "queues a fast first post and keeps the cover id in the queue" do
      result = submit_first_topic(user, cover_upload_id: upload.id)

      expect(result.action).to eq(:enqueued)
      expect(result.reviewable).to be_present

      reviewable = ReviewableQueuedPost.find(result.reviewable.id)
      expect(
        reviewable.payload.dig(
          "topic_opts",
          "custom_fields",
          DiscourseTopicCover::UPLOAD_ID_FIELD,
        ).to_s,
      ).to eq(upload.id.to_s)

      # The pending cover is referenced by the reviewable so the orphaned
      # upload cleanup cannot remove it while the post waits for review.
      expect(UploadReference.exists?(target: reviewable, upload: upload)).to eq(true)
      expect(ReviewableQueuedPost.where(target_created_by_id: user.id).pending.count).to eq(1)
    end

    it "saves the cover, dimensions and thumbnail data when an admin approves" do
      result = submit_first_topic(user, cover_upload_id: upload.id)
      reviewable = ReviewableQueuedPost.find(result.reviewable.id)

      perform_result = reviewable.perform(admin, :approve_post)
      expect(perform_result.success?).to eq(true)

      topic = reviewable.reload.target.topic
      expect(topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
      expect(topic.custom_fields[DiscourseTopicCover::UPLOAD_URL_FIELD]).to eq(upload.url)
      expect(topic.custom_fields[DiscourseTopicCover::UPLOAD_WIDTH_FIELD].to_i).to eq(upload.width)
      expect(topic.custom_fields[DiscourseTopicCover::UPLOAD_HEIGHT_FIELD].to_i).to eq(
        upload.height,
      )

      # The durable reference now lives on the topic's custom field, even
      # though the approval path skips the regular topic_created event.
      field =
        TopicCustomField.find_by!(
          topic_id: topic.id,
          name: DiscourseTopicCover::UPLOAD_ID_FIELD,
        )
      expect(UploadReference.exists?(target: field, upload: upload)).to eq(true)
    end

    it "still rejects a cover owned by another user before queueing" do
      other_user = Fabricate(:user)
      result = submit_first_topic(other_user, cover_upload_id: upload.id)

      expect(result.success?).to eq(false)
      expect(result.errors.full_messages.join(" ")).to include(
        I18n.t("discourse_topic_cover.errors.invalid"),
      )
      expect(ReviewableQueuedPost.where(target_created_by_id: other_user.id).count).to eq(0)
    end

    it "still requires a cover before queueing" do
      result = submit_first_topic(user, cover_upload_id: nil)

      expect(result.success?).to eq(false)
      expect(result.errors.full_messages.join(" ")).to include(
        I18n.t("discourse_topic_cover.errors.required"),
      )
      expect(ReviewableQueuedPost.count).to eq(0)
    end
  end
end
