# frozen_string_literal: true

RSpec.describe "Discourse body covers" do
  fab!(:user)
  fab!(:category)
  fab!(:upload) do
    Fabricate(:upload, user: user, original_filename: "cover.png", extension: "png", width: 1200, height: 675)
  end

  before do
    SiteSetting.topic_cover_enabled = true
    SiteSetting.topic_cover_required = true
  end

  def body(image = upload)
    "Topic body text\n\n![cover](#{image.short_url})"
  end

  def create_topic(raw)
    PostCreator.create(user, title: "A topic with a body cover", raw: raw, category: category.id)
  end

  it "rejects a body without a cover even when a stale cover ID is supplied" do
    creator = PostCreator.new(user, title: "Stale cover payload topic", raw: "Topic body text",
      topic_opts: { custom_fields: { DiscourseTopicCover::UPLOAD_ID_FIELD => upload.id } })
    creator.create
    expect(creator.errors.full_messages.join).to include(I18n.t("discourse_topic_cover.errors.required"))
  end

  it "derives the cover and its durable reference from the body" do
    post = create_topic(body)
    expect(post.errors).to be_empty
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
    field = TopicCustomField.find_by!(topic_id: post.topic_id, name: DiscourseTopicCover::UPLOAD_ID_FIELD)
    expect(UploadReference.exists?(target: field, upload_id: upload.id)).to eq(true)
  end

  it "allows an imageless body when the required switch is off" do
    SiteSetting.topic_cover_required = false
    post = create_topic("An optional cover topic body")
    expect(post.errors).to be_empty
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD]).to be_blank
  end

  it "does not accept an image URL in a link or code block as an embedded image" do
    expect(DiscourseTopicCover::BodyCover.find("[image](#{upload.short_url})", user)).to be_nil
    expect(DiscourseTopicCover::BodyCover.find("```\n![cover](#{upload.short_url})\n```", user)).to be_nil
  end

  it "rejects another member's upload but accepts a deduplicated association" do
    other = Fabricate(:user)
    expect(DiscourseTopicCover::BodyCover.find(body, other)).to be_nil
    UserUpload.create!(user: other, upload: upload)
    expect(DiscourseTopicCover::BodyCover.find(body, other)).to eq(upload)
  end

  it "selects the first qualifying rendered image" do
    small = Fabricate(:upload, user: user, width: 100, height: 100, original_filename: "small.png", extension: "png")
    expect(DiscourseTopicCover::BodyCover.find("#{body(small)}\n\n#{body}", user)).to eq(upload)
  end

  it "retains the body cover through enqueue and real approval" do
    result = NewPostManager.new(user, title: "A queued body cover topic", raw: body, category: category.id).enqueue(:fast_typer)
    expect(result).to be_success
    reviewable = result.reviewable.reload
    expect(reviewable.payload["raw"]).to include(upload.short_url)
    approved = reviewable.perform(Fabricate(:admin), :approve_post)
    expect(approved).to be_success
    expect(reviewable.reload.target.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
  end

  it "rejects removal of the last body image when required" do
    post = create_topic(body)
    revisor = PostRevisor.new(post)
    expect(revisor.revise!(user, { raw: "Body with the image removed" })).to eq(false)
    expect(post.reload.raw).to include(upload.short_url)
  end

  it "clears the cover when the image is removed with enforcement disabled" do
    post = create_topic(body)
    SiteSetting.topic_cover_required = false
    expect(PostRevisor.new(post).revise!(user, { raw: "Body with the optional image removed" })).to eq(true)
    expect(post.topic.reload.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD]).to be_blank
  end
end
