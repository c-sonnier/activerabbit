FactoryBot.define do
  factory :uptime_monitor do
    association :account
    association :project
    name { "Test Monitor" }
    sequence(:url) { |n| "https://example-#{n}.com/health" }
    http_method { "GET" }
    expected_status_code { 200 }
    interval_seconds { 300 }
    timeout_seconds { 30 }
    status { "pending" }
    alert_threshold { 3 }
  end
end
