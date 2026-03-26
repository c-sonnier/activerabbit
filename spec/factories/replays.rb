FactoryBot.define do
  factory :replay do
    association :account
    association :project
    sequence(:replay_id) { |n| SecureRandom.uuid }
    sequence(:session_id) { |n| SecureRandom.uuid }
    status { "ready" }
    started_at { 1.hour.ago }
    duration_ms { 30_000 }
    event_count { 150 }
    compressed_size { 5000 }
    uncompressed_size { 25_000 }
    storage_key { "replays/#{account_id}/#{project_id}/#{replay_id}" }
    checksum_sha256 { SecureRandom.hex(16) }
    retention_until { 30.days.from_now }
    url { "https://example.com/dashboard" }
    environment { "production" }
    uploaded_at { 1.hour.ago }

    trait :pending do
      status { "pending" }
      storage_key { nil }
      uploaded_at { nil }
    end

    trait :with_issue do
      association :issue
    end

    trait :expired do
      retention_until { 1.day.ago }
    end
  end
end
