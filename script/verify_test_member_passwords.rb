# frozen_string_literal: true

require "json"

user_a = User.find_by_username("cover_member_a")
user_b = User.find_by_username("cover_member_b")

checks = {
  a_password_valid: user_a.confirm_password?(ENV.fetch("TEST_PASSWORD_A")),
  a_email_confirmed: user_a.email_confirmed?,
  b_password_valid: user_b.confirm_password?(ENV.fetch("TEST_PASSWORD_B")),
  b_email_confirmed: user_b.email_confirmed?,
}

puts JSON.pretty_generate(checks)
exit(checks.values.all? ? 0 : 1)
