# frozen_string_literal: true

RSpec.describe "Required button-uploaded topic cover" do
  fab!(:user)
  fab!(:category)
  fab!(:upload) do
    Fabricate(:upload, user: user, original_filename: "cover.png", extension: "png", width: 1200, height: 675)
  end
  before { SiteSetting.topic_cover_enabled = true }

  def body
    "![topic-cover-#{upload.id}](#{upload.short_url})\n\nTopic body text"
  end

  it "rejects a missing cover" do
    creator = PostCreator.new(user, title: "A topic without its cover", raw: "Topic body text")
    creator.create
    expect(creator.errors.full_messages.join).to include(I18n.t("discourse_topic_cover.errors.required"))
  end

  it "rejects an ordinary body image without the explicit cover designation" do
    expect(DiscourseTopicCover::BodyCover.find("![image](#{upload.short_url})", user)).to be_nil
  end

  it "accepts the designated first-line cover" do
    expect(DiscourseTopicCover::BodyCover.find(body, user)).to eq(upload)
  end

  it "rejects a moved or duplicated cover" do
    expect(DiscourseTopicCover::BodyCover.find("Text first\n#{body}", user)).to be_nil
    expect(DiscourseTopicCover::BodyCover.find("#{body}\n#{body}", user)).to be_nil
  end

  it "rejects foreign uploads and accepts a deduplicated association" do
    other = Fabricate(:user)
    expect(DiscourseTopicCover::BodyCover.find(body, other)).to be_nil
    UserUpload.create!(user: other, upload: upload)
    expect(DiscourseTopicCover::BodyCover.find(body, other)).to eq(upload)
  end

  it "persists the selected cover when a topic is created" do
    post = PostCreator.create(user, title: "A topic with its selected cover", raw: body, category: category.id)
    expect(post.errors).to be_empty
    expect(post.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
  end

  it "keeps the cover in the queue and during approval" do
    result = NewPostManager.new(user, title: "A queued selected cover topic", raw: body, category: category.id).enqueue(:fast_typer)
    expect(result).to be_success
    reviewable = result.reviewable.reload
    expect(reviewable.payload["raw"]).to eq(body)
    expect(reviewable.perform(Fabricate(:admin), :approve_post)).to be_success
    expect(reviewable.reload.target.topic.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i).to eq(upload.id)
  end

  it "rejects deleting the selected cover while editing" do
    post = PostCreator.create(user, title: "A topic whose cover is required", raw: body, category: category.id)
    expect(PostRevisor.new(post).revise!(user, { raw: "Body without its cover" })).to eq(false)
    expect(post.reload.raw).to eq(body)
  end
end
