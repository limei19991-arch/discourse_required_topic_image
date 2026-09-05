# frozen_string_literal: true

module DiscourseTopicCover
  module BodyCover
    def self.find(raw, users)
      return if raw.blank?
      # The button places an explicit upload ID on the first line. Neither a
      # random body image nor an old custom-field ID satisfies this contract.
      match = raw.lines.first.to_s.strip.match(/\A!\[topic-cover-(\d+)\]\(([^\r\n]+)\)\z/)
      return unless match
      return unless raw.scan(/^!\[topic-cover-\d+\]\(/).length == 1

      id = match[1].to_i
      document = Nokogiri::HTML.fragment(PrettyText.cook(raw))
      images = document.css("img[src]")
      return unless images.first && Upload.extract_upload_ids(images.first["src"]).include?(id)
      return unless images.count { |image| Upload.extract_upload_ids(image["src"]).include?(id) } == 1

      Array(users).compact.each do |user|
        upload = UploadManager.find_valid_upload(id, user)
        return upload if upload
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
