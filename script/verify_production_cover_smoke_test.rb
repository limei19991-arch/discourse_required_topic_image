# frozen_string_literal: true

require "json"

user_a = User.find_by!(username_lower: "cover_member_a")
user_b = User.find_by!(username_lower: "cover_member_b")
topic_a = Topic.find(15)
topic_b = Topic.find(16)
shared_upload = Upload.find(14)
owner_only_upload = Upload.find(15)

checks = {
  user_a_is_active_member: user_a.active && !user_a.admin && !user_a.moderator,
  user_b_is_active_member: user_b.active && !user_b.admin && !user_b.moderator,
  topic_a_owned_by_user_a: topic_a.user_id == user_a.id,
  topic_b_owned_by_user_b: topic_b.user_id == user_b.id,
  topic_a_cover_persisted:
    topic_a.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i == shared_upload.id,
  topic_b_cover_persisted:
    topic_b.custom_fields[DiscourseTopicCover::UPLOAD_ID_FIELD].to_i == shared_upload.id,
  user_a_linked_to_shared_upload:
    UserUpload.exists?(user_id: user_a.id, upload_id: shared_upload.id),
  user_b_linked_to_shared_upload:
    UserUpload.exists?(user_id: user_b.id, upload_id: shared_upload.id),
  shared_upload_valid_for_user_a:
    DiscourseTopicCover::UploadManager.valid_upload_for_user?(shared_upload.id, user_a),
  deduplicated_upload_valid_for_user_b:
    DiscourseTopicCover::UploadManager.valid_upload_for_user?(shared_upload.id, user_b),
  owner_only_upload_rejected_for_user_b:
    !DiscourseTopicCover::UploadManager.valid_upload_for_user?(owner_only_upload.id, user_b),
  unauthorized_topic_not_created: Topic.where("title LIKE ?", "[插件测试] 越权检查%").none?,
}

result = {
  checks: checks,
  passed: checks.values.all?,
  topics: [
    { id: topic_a.id, url: "#{Discourse.base_url}/t/#{topic_a.id}" },
    { id: topic_b.id, url: "#{Discourse.base_url}/t/#{topic_b.id}" },
  ],
}

puts JSON.pretty_generate(result)
exit(checks.values.all? ? 0 : 1)
