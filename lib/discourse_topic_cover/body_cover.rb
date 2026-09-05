# frozen_string_literal: true

module DiscourseTopicCover
  module BodyCover
    def self.find(raw, users)
      return if raw.blank?

      # Parse rendered images only: links and fenced code must not satisfy the rule.
      document = Nokogiri::HTML.fragment(PrettyText.cook(raw))
      document.css("img[src]").each do |image|
        Upload.extract_upload_ids(image["src"]).each do |id|
          Array(users).compact.each do |user|
            upload = UploadManager.find_valid_upload(id, user)
            return upload if upload
          end
        end
      end
      nil
    end

    def self.apply(topic, upload)
      fields = [UPLOAD_ID_FIELD, UPLOAD_URL_FIELD, UPLOAD_WIDTH_FIELD, UPLOAD_HEIGHT_FIELD]
      fields.each { |field| topic.custom_fields.delete(field) }
      return unless upload

      variant = UploadManager.cover_variant(upload)
      topic.custom_fields[UPLOAD_ID_FIELD] = upload.id
      topic.custom_fields[UPLOAD_URL_FIELD] = variant[:url]
      topic.custom_fields[UPLOAD_WIDTH_FIELD] = variant[:width]
      topic.custom_fields[UPLOAD_HEIGHT_FIELD] = variant[:height]
    end
  end
end
