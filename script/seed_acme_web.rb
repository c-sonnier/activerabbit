# Run with: bin/rails runner script/seed_acme_web.rb
#
# Seeds replays + additional logs for acme-web project.

ActsAsTenant.without_tenant do
  project = Project.find_by!(slug: "acme-web")
  account = project.account
  issues = project.issues.limit(10).to_a

  puts "=== Seeding acme-web (account: #{account.id}) ==="

  # ── Replays ──────────────────────────────────────────
  urls = [
    "https://acme.com/dashboard",
    "https://acme.com/settings",
    "https://acme.com/checkout",
    "https://acme.com/products/widget-pro",
    "https://acme.com/onboarding/step-2",
    "https://acme.com/account/billing",
    "https://acme.com/search?q=widgets",
    "https://acme.com/orders/1234"
  ]

  user_agents = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/119.0.0.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Mobile/15E148",
    "Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile"
  ]

  viewports = [[1920, 1080], [1440, 900], [1366, 768], [375, 812], [390, 844]]
  trigger_types = [nil, nil, nil, "error", "error", "click", "rage_click"]
  error_classes = %w[TypeError ReferenceError NetworkError TimeoutError]
  error_messages = [
    "Cannot read properties of undefined (reading 'map')",
    "fetchCart is not defined",
    "Failed to fetch /api/checkout",
    "Request timed out after 30000ms"
  ]

  25.times do |i|
    started = rand(96).hours.ago + rand(3600).seconds
    duration = rand(3_000..180_000)
    viewport = viewports.sample
    trigger = trigger_types.sample
    error_idx = rand(error_classes.length)

    Replay.create!(
      account: account, project: project,
      issue: trigger == "error" ? issues.sample : nil,
      replay_id: SecureRandom.uuid, session_id: SecureRandom.uuid,
      segment_index: 0, status: "ready",
      storage_key: "replays/#{account.id}/#{project.id}/#{SecureRandom.uuid}",
      started_at: started,
      captured_at: started + (duration / 1000.0).seconds,
      uploaded_at: started + (duration / 1000.0).seconds + rand(5).seconds,
      duration_ms: duration, event_count: rand(50..2000),
      compressed_size: rand(5_000..500_000),
      uncompressed_size: rand(50_000..5_000_000),
      url: urls.sample, user_agent: user_agents.sample,
      viewport_width: viewport[0], viewport_height: viewport[1],
      environment: %w[production production production staging].sample,
      release_version: "2.#{rand(0..5)}.#{rand(0..15)}",
      sdk_version: "0.2.#{rand(0..5)}",
      rrweb_version: "2.0.0-alpha.#{rand(10..17)}",
      schema_version: 1,
      checksum_sha256: SecureRandom.hex(32),
      retention_until: 30.days.from_now,
      trigger_type: trigger,
      trigger_error_class: trigger == "error" ? error_classes[error_idx] : nil,
      trigger_error_short: trigger == "error" ? error_messages[error_idx] : nil,
      trigger_offset_ms: trigger == "error" ? rand(1000..duration) : nil,
    )
    print "."
  end
  puts "\n  Created 25 replays"

  # ── Logs ─────────────────────────────────────────────
  log_templates = [
    { level: 2, message: "User signed in", source: "SessionsController#create" },
    { level: 2, message: "Order placed successfully", source: "OrdersController#create" },
    { level: 2, message: "Payment processed", source: "PaymentsService#charge" },
    { level: 2, message: "Email sent: order confirmation", source: "OrderMailer#confirmation" },
    { level: 2, message: "Cache hit for product catalog", source: "ProductsController#index" },
    { level: 2, message: "Background job enqueued: generate_invoice", source: "InvoiceJob" },
    { level: 1, message: "SQL query took 245ms", source: "ActiveRecord" },
    { level: 1, message: "Redis connection pool: 3/10 active", source: "RedisPool" },
    { level: 3, message: "Slow query detected: 1.2s on orders table", source: "ActiveRecord" },
    { level: 3, message: "Rate limit approaching: 80% of quota used", source: "RateLimiter" },
    { level: 3, message: "Retry attempt 2/3 for Stripe webhook", source: "WebhookProcessor" },
    { level: 3, message: "Memory usage at 85% of container limit", source: "HealthCheck" },
    { level: 4, message: "Stripe::CardError: card_declined", source: "PaymentsService#charge" },
    { level: 4, message: "ActionController::RoutingError: No route matches /api/v2/users", source: "Router" },
    { level: 4, message: "Redis connection timeout after 5s", source: "CacheStore" },
    { level: 4, message: "PG::UniqueViolation: duplicate key value violates unique constraint", source: "OrdersController#create" },
    { level: 5, message: "Sidekiq process terminated unexpectedly", source: "Sidekiq" },
    { level: 5, message: "Database connection pool exhausted", source: "ActiveRecord" },
    { level: 0, message: "Request started: GET /api/v1/products", source: "ActionDispatch" },
    { level: 0, message: "Params: {page: 1, per: 25, category: 'electronics'}", source: "ActionDispatch" }
  ]

  150.times do |i|
    template = log_templates.sample
    occurred = rand(48).hours.ago + rand(3600).seconds
    trace_id = rand < 0.4 ? SecureRandom.hex(16) : nil

    LogEntry.create!(
      account: account, project: project,
      issue: template[:level] >= 4 && issues.any? ? issues.sample : nil,
      level: template[:level],
      message: template[:message],
      source: template[:source],
      occurred_at: occurred,
      trace_id: trace_id,
      request_id: trace_id ? SecureRandom.hex(8) : nil,
      environment: %w[production production staging].sample,
      params: template[:level] <= 1 ? { "duration_ms" => rand(1..500), "status" => 200 } : nil,
      context: { "host" => "web-#{rand(1..4)}", "pid" => rand(1000..9999) },
    )
    print "."
  end
  puts "\n  Created 150 log entries"

  puts "\nDone! View at:"
  puts "  Replays: http://localhost:3003/acme-web/replays"
  puts "  Logs:    http://localhost:3003/logs"
end
