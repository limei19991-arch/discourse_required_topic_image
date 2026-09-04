# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tempfile"

ROLE_SPECS = [
  { username: "cover_tl0", name: "封面测试 新用户", trust_level: 0, admin: false, moderator: false },
  { username: "cover_tl1", name: "封面测试 基本成员", trust_level: 1, admin: false, moderator: false },
  { username: "cover_tl2", name: "封面测试 成员", trust_level: 2, admin: false, moderator: false },
  { username: "cover_moderator", name: "封面测试 版主", trust_level: 4, admin: false, moderator: true },
  { username: "cover_admin", name: "封面测试 管理员", trust_level: 4, admin: true, moderator: false },
].freeze

def ensure_test_user(spec)
  password = "Ac!#{SecureRandom.base58(16)}"
  user = User.find_by(username_lower: spec[:username].downcase)

  if user
    user.password = password
    user.name = spec[:name]
  else
    user =
      User.new(
        username: spec[:username],
        name: spec[:name],
        email: "#{spec[:username]}@example.com",
        password: password,
      )
  end

  user.active = true
  user.approved = true
  user.admin = spec[:admin]
  user.moderator = spec[:moderator]
  user.trust_level = spec[:trust_level]
  user.save!
  user.activate unless user.email_confirmed?
  user.reload

  [user, password]
end

def upload_image_for(user, source_path, filename)
  tempfile = Tempfile.new(["topic-cover-role-", File.extname(filename)])
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

def create_topic(user:, upload:, category:, label:)
  creator =
    PostCreator.new(
      user,
      title: "[权限测试] #{label} #{Time.zone.now.strftime("%Y%m%d-%H%M%S-%L")}",
      raw: "这是 discourse-topic-cover 多权限账号封面上传测试帖。",
      category: category.id,
      topic_opts: {
        custom_fields: {
          DiscourseTopicCover::UPLOAD_ID_FIELD => upload.id,
        },
      },
    )
  post = creator.create

  {
    success: post.present? && creator.errors.empty?,
    errors: creator.errors.full_messages,
    topic_id: post&.topic_id,
    url: post&.topic_id ? "#{Discourse.base_url}/t/#{post.topic_id}" : nil,
  }
end

accounts = ROLE_SPECS.map { |spec| [spec, *ensure_test_user(spec)] }
users = accounts.to_h { |spec, user, _password| [spec[:username], user] }

category =
  Category
    .where(read_restricted: false)
    .order(:position)
    .detect do |candidate|
      users.values.all? { |user| Guardian.new(user).can_create_topic_on_category?(candidate) }
    end
raise "No public category is writable by every role-test account" if category.blank?

shared_path = "/tmp/topic-cover-role-shared.png"
owner_only_path = "/tmp/topic-cover-role-owner-only.png"
shared_uploads =
  users.to_h do |username, user|
    [username, upload_image_for(user, shared_path, "role-shared-cover.png")]
  end
shared_upload = shared_uploads.values.first
owner_only_upload =
  upload_image_for(users.fetch("cover_tl0"), owner_only_path, "role-owner-only-cover.png")

role_posts =
  users.to_h do |username, user|
    [
      username,
      create_topic(
        user: user,
        upload: shared_uploads.fetch(username),
        category: category,
        label: username,
      ),
    ]
  end

tl1 = users.fetch("cover_tl1")
moderator = users.fetch("cover_moderator")
admin = users.fetch("cover_admin")

unauthorized_member_post =
  create_topic(
    user: tl1,
    upload: owner_only_upload,
    category: category,
    label: "普通成员越权图片（应失败）",
  )
moderator_foreign_post =
  create_topic(
    user: moderator,
    upload: owner_only_upload,
    category: category,
    label: "版主使用其他用户图片",
  )
admin_foreign_post =
  create_topic(
    user: admin,
    upload: owner_only_upload,
    category: category,
    label: "管理员使用其他用户图片",
  )

checks = {
  accounts_active_and_confirmed:
    users.values.all? { |user| user.active && user.email_confirmed? && user.has_password? },
  roles_match:
    ROLE_SPECS.all? do |spec|
      user = users.fetch(spec[:username])
      user.trust_level == spec[:trust_level] && user.admin == spec[:admin] &&
        user.moderator == spec[:moderator]
    end,
  shared_upload_deduplicated: shared_uploads.values.map(&:id).uniq == [shared_upload.id],
  every_uploader_linked:
    users.values.all? do |user|
      UserUpload.exists?(user_id: user.id, upload_id: shared_upload.id)
    end,
  shared_upload_valid_for_every_role:
    users.values.all? do |user|
      DiscourseTopicCover::UploadManager.valid_upload_for_user?(shared_upload.id, user)
    end,
  every_role_post_succeeded: role_posts.values.all? { |result| result[:success] },
  member_foreign_upload_rejected:
    !DiscourseTopicCover::UploadManager.valid_upload_for_user?(owner_only_upload.id, tl1),
  member_foreign_topic_not_created:
    !unauthorized_member_post[:success] && unauthorized_member_post[:topic_id].nil?,
  moderator_staff_override_works:
    DiscourseTopicCover::UploadManager.valid_upload_for_user?(owner_only_upload.id, moderator) &&
      moderator_foreign_post[:success],
  admin_staff_override_works:
    DiscourseTopicCover::UploadManager.valid_upload_for_user?(owner_only_upload.id, admin) &&
      admin_foreign_post[:success],
}

result = {
  site: Discourse.base_url,
  category: { id: category.id, name: category.name, slug: category.slug },
  accounts:
    accounts.map do |spec, user, password|
      {
        username: user.username,
        password: password,
        trust_level: user.trust_level,
        admin: user.admin,
        moderator: user.moderator,
        active: user.active,
        email_confirmed: user.email_confirmed?,
      }
    end,
  uploads: {
    shared_upload_id: shared_upload.id,
    per_user_upload_ids: shared_uploads.transform_values(&:id),
    owner_only_upload_id: owner_only_upload.id,
  },
  posts: {
    per_role: role_posts,
    member_foreign_upload: unauthorized_member_post,
    moderator_foreign_upload: moderator_foreign_post,
    admin_foreign_upload: admin_foreign_post,
  },
  checks: checks,
  passed: checks.values.all?,
}

puts JSON.pretty_generate(result)
exit(checks.values.all? ? 0 : 1)
