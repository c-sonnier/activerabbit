# Run with: bin/rails runner script/seed_replays.rb
#
# Generates sample session replays for the first real project found.

ActsAsTenant.without_tenant do
  # Pick the first project with a real account
  project = Project.find_by(slug: "nextjs") || Project.first
  account = project.account

  puts "Seeding replays for project: #{project.slug} (account: #{account.id})"

  urls = [
    "https://app.example.com/dashboard",
    "https://app.example.com/settings/profile",
    "https://app.example.com/checkout",
    "https://app.example.com/products/123",
    "https://app.example.com/onboarding",
    "https://app.example.com/login",
    "https://app.example.com/billing",
    "https://app.example.com/reports/weekly",
  ]

  user_agents = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/119.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36",
  ]

  viewports = [
    [1920, 1080], [1440, 900], [1366, 768], [375, 812], [390, 844], [1536, 864],
  ]

  environments = %w[production staging]
  trigger_types = [nil, nil, nil, "error", "error", "click", "rage_click"]
  error_classes = ["TypeError", "ReferenceError", "SyntaxError", "NetworkError", "TimeoutError"]
  error_messages = [
    "Cannot read properties of undefined (reading 'map')",
    "fetchUserData is not defined",
    "Unexpected token '<'",
    "Failed to fetch",
    "Request timed out after 30000ms",
  ]

  issues = project.issues.limit(5).to_a

  20.times do |i|
    started = rand(72).hours.ago + rand(3600).seconds
    duration = rand(5_000..180_000)
    viewport = viewports.sample
    trigger = trigger_types.sample
    error_idx = rand(error_classes.length)

    replay = Replay.create!(
      account: account,
      project: project,
      issue: trigger == "error" ? issues.sample : nil,
      replay_id: SecureRandom.uuid,
      session_id: SecureRandom.uuid,
      segment_index: 0,
      status: "ready",
      storage_key: "replays/#{account.id}/#{project.id}/#{SecureRandom.uuid}",
      started_at: started,
      captured_at: started + (duration / 1000.0).seconds,
      uploaded_at: started + (duration / 1000.0).seconds + rand(5).seconds,
      duration_ms: duration,
      event_count: rand(50..2000),
      compressed_size: rand(5_000..500_000),
      uncompressed_size: rand(50_000..5_000_000),
      url: urls.sample,
      user_agent: user_agents.sample,
      viewport_width: viewport[0],
      viewport_height: viewport[1],
      environment: environments.sample,
      release_version: "1.#{rand(0..9)}.#{rand(0..20)}",
      sdk_version: "0.#{rand(1..3)}.#{rand(0..5)}",
      rrweb_version: "2.0.0-alpha.#{rand(10..17)}",
      schema_version: 1,
      checksum_sha256: SecureRandom.hex(32),
      retention_until: 30.days.from_now,
      trigger_type: trigger,
      trigger_error_class: trigger == "error" ? error_classes[error_idx] : nil,
      trigger_error_short: trigger == "error" ? error_messages[error_idx] : nil,
      trigger_offset_ms: trigger == "error" ? rand(1000..duration) : nil,
    )

    puts "  Created replay ##{i + 1}: #{replay.replay_id[0..7]}... (#{(duration / 1000.0).round(1)}s, #{replay.url})"
  end

  puts "\nDone! Created 20 replays for #{project.slug}."
  puts "View at: http://localhost:3003/#{project.slug}/replays"
end
