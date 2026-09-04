# frozen_string_literal: true

RSpec.describe "Discourse Topic Cover" do
  fab!(:user)
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
end
