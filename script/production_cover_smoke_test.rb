# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tempfile"

def ensure_test_member(username:, name:, email:)
  password = "Ac!#{SecureRandom.base58(16)}"
  user = User.find_by(username_lower: username.downcase)

  if user
    user.password = password
    user.name = name
  else
    user = User.new(username: username, name: name, email: email, password: password)
  end

  user.active = true
  user.approved = true
  user.admin = false
  user.moderator = false
  user.trust_level = 1
  user.save!
  user.activate unless user.email_confirmed?

  [user, password]
end

def upload_image_for(user, source_path, filename)
  tempfile = Tempfile.new(["topic-cover-smoke-", File.extname(filename)])
  tempfile.binmode
  FileUtils.copy_file(source_path, tempfile.path)
  tempfile.rewind

  upload = UploadCreator.new(tempfile, filename, type: "topic_cover").create_for(user.id)
  raise "Upload failed for #{user.username}: #{upload.errors.full_messages.join(", ")}" if
    upload.errors.present?

  upload
ensure
  tempfile&.close
end

def create_cover_topic(user:, upload:, category:, label:)
  creator = PostCreator.new(
    user,
    title: "[插件测试] #{label} #{Time.zone.now.strftime("%Y%m%d-%H%M%S")}",
    raw: "这是 discourse-topic-cover 普通成员上传封面的自动测试帖。",
    category: category.id,
    topic_opts: {
      custom_fields: {
        DiscourseTopicCover::UPLOAD_ID_FIELD => upload.id,
      },
    },
  )
  post = creator.create

  { post: post, errors: creator.errors.full_messages }
end

user_a, password_a =
  ensure_test_member(
    username: "cover_member_a",
    name: "封面测试成员 A",
    email: "cover-member-a@example.com",
  )
user_b, password_b =
  ensure_test_member(
    username: "cover_member_b",
    name: "封面测试成员 B",
    email: "cover-member-b@example.com",
  )

category =
  Category
    .where(read_restricted: false)
    .order(:position)
    .detect do |candidate|
      Guardian.new(user_a).can_create_topic_on_category?(candidate) &&
        Guardian.new(user_b).can_create_topic_on_category?(candidate)
    end
raise "No public category is writable by both test members" if category.blank?

shared_path = "/tmp/topic-cover-shared.png"
owner_only_path = "/tmp/topic-cover-owner-only.png"

upload_a = upload_image_for(user_a, shared_path, "shared-cover.png")
upload_b = upload_image_for(user_b, shared_path, "shared-cover.png")
owner_only_upload = upload_image_for(user_a, owner_only_path, "owner-only-cover.png")

post_a =
  create_cover_topic(user: user_a, upload: upload_a, category: category, label: "原始上传者")
post_b =
  create_cover_topic(user: user_b, upload: upload_b, category: category, label: "去重图片上传者")
unauthorized_post =
  create_cover_topic(user: user_b, upload: owner_only_upload, category: category, label: "越权检查")

result = {
  site: Discourse.base_url,
  secure_uploads: SiteSetting.secure_uploads,
  category: { id: category.id, name: category.name, slug: category.slug },
  accounts: [
    {
      username: user_a.username,
      password: password_a,
      admin: user_a.admin,
      moderator: user_a.moderator,
      active: user_a.active,
    },
    {
      username: user_b.username,
      password: password_b,
      admin: user_b.admin,
      moderator: user_b.moderator,
      active: user_b.active,
    },
  ],
  uploads: {
    user_a_upload_id: upload_a.id,
    user_b_upload_id: upload_b.id,
    deduplicated_to_same_upload: upload_a.id == upload_b.id,
    user_b_has_user_upload: UserUpload.exists?(user_id: user_b.id, upload_id: upload_b.id),
    user_b_upload_is_valid: DiscourseTopicCover::UploadManager.valid_upload_for_user?(
      upload_b.id,
      user_b,
    ),
    owner_only_upload_id: owner_only_upload.id,
    owner_only_rejected_for_user_b: !DiscourseTopicCover::UploadManager.valid_upload_for_user?(
      owner_only_upload.id,
      user_b,
    ),
  },
  posts: {
    user_a: {
      success: post_a[:post].present? && post_a[:errors].empty?,
      errors: post_a[:errors],
      topic_id: post_a[:post]&.topic_id,
      url: post_a[:post]&.topic_id ? "#{Discourse.base_url}/t/#{post_a[:post].topic_id}" : nil,
    },
    user_b_deduplicated: {
      success: post_b[:post].present? && post_b[:errors].empty?,
      errors: post_b[:errors],
      topic_id: post_b[:post]&.topic_id,
      url: post_b[:post]&.topic_id ? "#{Discourse.base_url}/t/#{post_b[:post].topic_id}" : nil,
    },
    user_b_unauthorized: {
      rejected: unauthorized_post[:post].blank? && unauthorized_post[:errors].present?,
      errors: unauthorized_post[:errors],
      topic_id: unauthorized_post[:post]&.topic_id,
    },
  },
}

puts JSON.pretty_generate(result)
