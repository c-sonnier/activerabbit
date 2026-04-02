# Seed log entries for the "localhost" project
# Run with: rails runner db/seeds/logs_localhost.rb

account = Account.find_by!(name: "Acme Corp")
ActsAsTenant.current_tenant = account

project = Project.find_or_create_by!(slug: "localhost") do |p|
  p.name        = "Localhost"
  p.url         = "http://localhost:3003"
  p.environment = "development"
  p.tech_stack  = "rails"
  p.account     = account
end

puts "Project: #{project.name} (slug: #{project.slug}, id: #{project.id})"

# Clean existing logs for this project
deleted = LogEntry.where(project: project).delete_all
puts "  Deleted #{deleted} existing log entries"

# ---------------------------------------------------------------------------
# Realistic log scenarios
# ---------------------------------------------------------------------------
scenarios = [
  # Normal request lifecycle
  { level: 2, source: "ActionController",       message: "Started GET / for 127.0.0.1",                           environment: "development" },
  { level: 2, source: "ActionController",       message: "Started POST /api/v1/events for 127.0.0.1",            environment: "development" },
  { level: 2, source: "ActionController",       message: "Completed 200 OK in 34ms (Views: 12.3ms | ActiveRecord: 8.1ms)", environment: "development" },
  { level: 2, source: "ActionController",       message: "Completed 201 Created in 18ms",                        environment: "development" },
  { level: 1, source: "ActiveRecord",           message: "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" = $1 LIMIT 1 [0.8ms]", environment: "development" },
  { level: 1, source: "ActiveRecord",           message: "INSERT INTO \"events\" (\"type\", \"occurred_at\") VALUES ($1, $2) [2.1ms]", environment: "development" },
  { level: 1, source: "ActiveRecord",           message: "SELECT COUNT(*) FROM \"log_entries\" WHERE \"project_id\" = $1 [1.2ms]", environment: "development" },

  # Background jobs
  { level: 2, source: "LogIngestJob",           message: "Processing batch of 25 log entries",                    environment: "development" },
  { level: 2, source: "LogIngestJob",           message: "Successfully ingested 25 entries in 42ms",             environment: "development" },
  { level: 2, source: "EventProcessorJob",      message: "Processed event: PageView from session abc123",        environment: "development" },
  { level: 2, source: "IssueGroupingJob",       message: "Grouped 3 new events into issue #142",                 environment: "development" },
  { level: 1, source: "Sidekiq",                message: "Enqueued LogIngestJob (queue: default) with args: [batch_id: 9f3a2b]", environment: "development" },

  # Warnings
  { level: 3, source: "QuotaChecker",           message: "Account approaching event quota: 45,230 / 50,000 (90%)", environment: "development" },
  { level: 3, source: "ActionController",       message: "Unpermitted parameters: [:admin, :debug_mode]",        environment: "development" },
  { level: 3, source: "ActiveRecord",           message: "Query took 850ms: SELECT * FROM events WHERE occurred_at > '2026-03-01' ORDER BY occurred_at DESC", environment: "development" },
  { level: 3, source: "Redis",                  message: "Connection pool exhausted, waited 200ms for available connection", environment: "development" },
  { level: 3, source: "ActionMailer",           message: "Email delivery to user@example.com delayed: SMTP timeout after 5s", environment: "development" },
  { level: 3, source: "Rack::Attack",           message: "Throttled 127.0.0.1 — 102 requests in 60s (limit: 100)", environment: "development" },

  # Errors
  { level: 4, source: "ActionController",       message: "NoMethodError: undefined method 'name' for nil:NilClass in ProjectsController#show", environment: "development" },
  { level: 4, source: "ActiveRecord",           message: "PG::UniqueViolation: duplicate key value violates unique constraint \"index_users_on_email\"", environment: "development" },
  { level: 4, source: "ApiTokenAuth",           message: "Authentication failed: invalid API token (prefix: ar_live_9x...)", environment: "development" },
  { level: 4, source: "ActionController",       message: "ActionController::ParameterMissing: param is missing or the value is empty: project", environment: "development" },
  { level: 4, source: "Net::HTTP",              message: "Connection refused — webhook delivery to https://hooks.slack.com/services/T01... failed", environment: "development" },
  { level: 4, source: "LogIngestJob",           message: "Failed to process batch abc123: payload exceeds 1MB limit", environment: "development" },

  # Debug
  { level: 1, source: "WebSocket",              message: "Client subscribed to LogStreamChannel (project_id: #{project.id})", environment: "development" },
  { level: 1, source: "WebSocket",              message: "Broadcasting to log_stream:#{project.id} — 1 entry",   environment: "development" },
  { level: 1, source: "ActionCable",            message: "LogStreamChannel transmitting to 2 subscribers",       environment: "development" },
  { level: 1, source: "Cache",                  message: "Cache hit: views/projects/show/#{project.id}-20260401 (0.3ms)", environment: "development" },
  { level: 1, source: "Cache",                  message: "Cache miss: views/logs/index — generating (12ms)",     environment: "development" },

  # Trace
  { level: 0, source: "Middleware",             message: "Request headers: Accept=application/json, X-Request-Id=req_abc123", environment: "development" },
  { level: 0, source: "Middleware",             message: "Response: 200, Content-Length: 4521, X-Runtime: 0.034", environment: "development" },

  # Fatal
  { level: 5, source: "ActiveRecord",           message: "FATAL: could not connect to PostgreSQL — Is the server running on localhost:5432?", environment: "development" },
  { level: 5, source: "Redis",                  message: "FATAL: Redis connection lost — Error connecting to Redis on 127.0.0.1:6379 (Errno::ECONNREFUSED)", environment: "development" },

  # Production-like logs mixed in
  { level: 2, source: "Deployer",               message: "Deployment v2.15.0 completed successfully",            environment: "production" },
  { level: 4, source: "Stripe::WebhookHandler", message: "Webhook signature verification failed for event evt_1N...", environment: "production" },
  { level: 3, source: "S3Storage",              message: "Upload retry #2 for attachment 8f2a — SlowDown response from S3", environment: "production" },
  { level: 2, source: "HealthCheck",            message: "All checks passing: db=ok redis=ok sidekiq=ok",       environment: "production" },
  { level: 4, source: "ActionController",       message: "Timeout::Error: execution expired after 30s in ReportsController#generate", environment: "production" },
]

# Generate ~200 log entries spread over the last 24 hours
total = 0
trace_ids = 5.times.map { "tr_#{SecureRandom.hex(6)}" }
request_ids = 10.times.map { "req_#{SecureRandom.hex(8)}" }

scenarios.each do |scenario|
  count = case scenario[:level]
          when 0 then rand(2..4)    # trace: few
          when 1 then rand(4..8)    # debug: moderate
          when 2 then rand(5..12)   # info: most common
          when 3 then rand(3..6)    # warn: some
          when 4 then rand(2..5)    # error: fewer
          when 5 then rand(1..2)    # fatal: rare
          end

  count.times do
    occurred = rand(24.hours).seconds.ago

    LogEntry.create!(
      account: account,
      project: project,
      level: scenario[:level],
      message: scenario[:message],
      source: scenario[:source],
      environment: scenario[:environment],
      params: {},
      context: {},
      trace_id: rand < 0.4 ? trace_ids.sample : nil,
      request_id: rand < 0.5 ? request_ids.sample : nil,
      occurred_at: occurred
    )
    total += 1
  end
end

puts "\n  Created #{total} log entries for '#{project.slug}'"
puts "    Trace:   #{LogEntry.where(project: project, level: 0).count}"
puts "    Debug:   #{LogEntry.where(project: project, level: 1).count}"
puts "    Info:    #{LogEntry.where(project: project, level: 2).count}"
puts "    Warning: #{LogEntry.where(project: project, level: 3).count}"
puts "    Error:   #{LogEntry.where(project: project, level: 4).count}"
puts "    Fatal:   #{LogEntry.where(project: project, level: 5).count}"
puts "\n  View at: http://localhost:3003/localhost/logs"
