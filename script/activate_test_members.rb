# frozen_string_literal: true

require "json"

results =
  %w[cover_member_a cover_member_b].map do |username|
    user = User.find_by!(username_lower: username)
    before = user.email_confirmed?
    user.activate unless before
    user.reload

    {
      username: user.username,
      active: user.active,
      admin: user.admin,
      moderator: user.moderator,
      email_confirmed_before: before,
      email_confirmed_after: user.email_confirmed?,
      password_present: user.has_password?,
    }
  end

puts JSON.pretty_generate(results)
exit(results.all? { |result| result[:active] && result[:email_confirmed_after] } ? 0 : 1)
