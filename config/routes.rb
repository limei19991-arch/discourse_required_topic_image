# frozen_string_literal: true

DiscourseTopicCover::Engine.routes.draw { put "/:topic_id" => "topic_covers#update" }
