# Seed error issues + events for the "localhost" project
# Run with: rails runner db/seeds/errors_localhost.rb

account = Account.find_by!(name: "Acme Corp")
ActsAsTenant.current_tenant = account

project = Project.find_by!(slug: "localhost")
users = account.users.to_a

puts "Project: #{project.name} (slug: #{project.slug}, id: #{project.id})"

# Clean existing issues/events for this project
event_count = Event.where(project: project).delete_all
issue_count = Issue.where(project: project).delete_all
puts "  Cleaned #{issue_count} issues and #{event_count} events"

base_context = {
  "ruby_version" => "3.3.0",
  "rails_version" => "8.0.2",
  "hostname" => "localhost",
  "pid" => 43210
}

# =========================================================================
# OPEN / WIP errors — recent activity
# =========================================================================
open_scenarios = [
  {
    exception_class: "NoMethodError",
    message: "undefined method 'name' for nil — Did you mean? names",
    backtrace: [
      "app/controllers/dashboard_controller.rb:28:in `show'",
      "app/views/dashboard/show.html.erb:14:in `_app_views_dashboard_show_html_erb__1234'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "DashboardController#show",
    request_path: "/dashboard",
    request_method: "GET",
    occurrences: 23,
    severity: "critical",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "ActiveRecord::RecordNotFound",
    message: "Couldn't find User with 'id'=999",
    backtrace: [
      "app/controllers/users_controller.rb:12:in `show'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "UsersController#show",
    request_path: "/users/999",
    request_method: "GET",
    occurrences: 15,
    severity: "high",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "PG::UniqueViolation",
    message: "duplicate key value violates unique constraint \"index_users_on_email\"",
    backtrace: [
      "app/models/user.rb:45:in `create_or_update'",
      "app/controllers/registrations_controller.rb:18:in `create'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "RegistrationsController#create",
    request_path: "/register",
    request_method: "POST",
    occurrences: 9,
    severity: "high",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "ActionController::ParameterMissing",
    message: "param is missing or the value is empty: project",
    backtrace: [
      "app/controllers/projects_controller.rb:55:in `project_params'",
      "app/controllers/projects_controller.rb:22:in `create'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "ProjectsController#create",
    request_path: "/projects",
    request_method: "POST",
    occurrences: 7,
    severity: "medium",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "Redis::CannotConnectError",
    message: "Error connecting to Redis on 127.0.0.1:6379 (Errno::ECONNREFUSED)",
    backtrace: [
      "app/services/cache_service.rb:12:in `fetch'",
      "app/controllers/api/v1/events_controller.rb:30:in `create'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "Api::V1::EventsController#create",
    request_path: "/api/v1/events",
    request_method: "POST",
    occurrences: 18,
    severity: "critical",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "Timeout::Error",
    message: "execution expired after 30s",
    backtrace: [
      "app/services/external_api_client.rb:22:in `fetch_data'",
      "app/controllers/reports_controller.rb:15:in `generate'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "ReportsController#generate",
    request_path: "/reports/generate",
    request_method: "POST",
    occurrences: 6,
    severity: "high",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "TypeError",
    message: "no implicit conversion of nil into String",
    backtrace: [
      "app/services/csv_exporter.rb:42:in `generate_row'",
      "app/services/csv_exporter.rb:18:in `block in export'",
      "app/controllers/exports_controller.rb:11:in `create'"
    ],
    controller_action: "ExportsController#create",
    request_path: "/exports",
    request_method: "POST",
    occurrences: 4,
    severity: "medium",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "ArgumentError",
    message: "wrong number of arguments (given 3, expected 2)",
    backtrace: [
      "app/services/notification_service.rb:28:in `send_email'",
      "app/controllers/notifications_controller.rb:10:in `create'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "NotificationsController#create",
    request_path: "/notifications",
    request_method: "POST",
    occurrences: 3,
    severity: "low",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "Net::ReadTimeout",
    message: "Net::ReadTimeout with #<TCPSocket:(closed)>",
    backtrace: [
      "app/services/webhook_delivery.rb:35:in `deliver'",
      "app/controllers/webhooks_controller.rb:20:in `create'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "WebhooksController#create",
    request_path: "/webhooks",
    request_method: "POST",
    occurrences: 11,
    severity: "high",
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "RuntimeError",
    message: "Stripe webhook signature verification failed",
    backtrace: [
      "app/controllers/webhooks/stripe_controller.rb:15:in `verify_signature!'",
      "app/controllers/webhooks/stripe_controller.rb:5:in `create'",
      "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
    ],
    controller_action: "Webhooks::StripeController#create",
    request_path: "/webhooks/stripe",
    request_method: "POST",
    occurrences: 5,
    severity: "medium",
    environment: "development",
    server_name: "localhost"
  }
]

# =========================================================================
# CLOSED errors — older, resolved
# =========================================================================
closed_scenarios = [
  {
    exception_class: "NameError",
    message: "uninitialized constant UserMailer::WELCOME_TEMPLATE",
    backtrace: [
      "app/mailers/user_mailer.rb:8:in `welcome'",
      "app/controllers/registrations_controller.rb:25:in `create'"
    ],
    controller_action: "RegistrationsController#create",
    request_path: "/register",
    request_method: "POST",
    occurrences: 3,
    first_seen: 5.days.ago,
    last_seen: 3.days.ago,
    environment: "development",
    server_name: "localhost"
  },
  {
    exception_class: "ActiveRecord::StatementInvalid",
    message: "PG::UndefinedColumn: ERROR: column \"deleted_at\" does not exist",
    backtrace: [
      "app/models/project.rb:15:in `soft_delete'",
      "app/controllers/projects_controller.rb:40:in `destroy'"
    ],
    controller_action: "ProjectsController#destroy",
    request_path: "/projects/3",
    request_method: "DELETE",
    occurrences: 2,
    first_seen: 7.days.ago,
    last_seen: 6.days.ago,
    environment: "development",
    server_name: "localhost"
  }
]

# =========================================================================
# FAILED JOBS — background job errors
# =========================================================================
job_scenarios = [
  {
    exception_class: "PG::ConnectionBad",
    message: "could not connect to server: Connection refused",
    backtrace: [
      "app/jobs/daily_report_job.rb:10:in `perform'",
      "activejob (8.0.2.1) lib/active_job/execution.rb:53:in `perform_now'"
    ],
    controller_action: "DailyReportJob#perform",
    request_path: nil,
    request_method: nil,
    occurrences: 7,
    first_seen: 2.days.ago,
    environment: "development",
    server_name: "worker-01",
    context: base_context.merge("job_context" => { "queue" => "default", "job_class" => "DailyReportJob" })
  },
  {
    exception_class: "Errno::ENOENT",
    message: "No such file or directory @ rb_sysopen - /tmp/export_20260401.csv",
    backtrace: [
      "app/jobs/export_cleanup_job.rb:8:in `perform'",
      "activejob (8.0.2.1) lib/active_job/execution.rb:53:in `perform_now'"
    ],
    controller_action: "ExportCleanupJob#perform",
    request_path: nil,
    request_method: nil,
    occurrences: 4,
    first_seen: 1.day.ago,
    environment: "development",
    server_name: "worker-01",
    context: base_context.merge("job_context" => { "queue" => "low", "job_class" => "ExportCleanupJob" })
  }
]

# =========================================================================
# Frontend JS errors
# =========================================================================
frontend_scenarios = [
  {
    exception_class: "TypeError",
    message: "Cannot read properties of undefined (reading 'map')",
    backtrace: [
      "app/javascript/controllers/dashboard_controller.js:45:12",
      "app/javascript/controllers/dashboard_controller.js:30:5"
    ],
    controller_action: "dashboard_controller.js#renderChart",
    request_path: "/dashboard",
    request_method: "GET",
    occurrences: 14,
    environment: "development",
    server_name: "browser",
    source: "frontend"
  },
  {
    exception_class: "ReferenceError",
    message: "Turbo is not defined",
    backtrace: [
      "app/javascript/application.js:12:1",
      "app/javascript/controllers/index.js:3:8"
    ],
    controller_action: "application.js#init",
    request_path: "/",
    request_method: "GET",
    occurrences: 8,
    environment: "development",
    server_name: "browser",
    source: "frontend"
  }
]

total_events = 0

# -- Ingest open/wip errors --
open_scenarios.each do |scenario|
  scenario[:occurrences].times do
    occurred = rand(24.hours.ago..Time.current)

    Event.ingest_error(
      project: project,
      payload: {
        exception_class:   scenario[:exception_class],
        message:           scenario[:message],
        backtrace:         scenario[:backtrace],
        controller_action: scenario[:controller_action],
        request_path:      scenario[:request_path],
        request_method:    scenario[:request_method],
        occurred_at:       occurred,
        environment:       scenario[:environment],
        server_name:       scenario[:server_name],
        request_id:        SecureRandom.uuid,
        user_id:           users.sample&.id&.to_s,
        context:           base_context,
        source:            scenario[:source]
      }
    )
    total_events += 1
  end
  puts "  [open]   #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
end

# -- Ingest closed errors --
closed_scenarios.each do |scenario|
  first = scenario[:first_seen] || 5.days.ago
  last = scenario[:last_seen] || 3.days.ago

  scenario[:occurrences].times do
    occurred = rand(first..last)

    Event.ingest_error(
      project: project,
      payload: {
        exception_class:   scenario[:exception_class],
        message:           scenario[:message],
        backtrace:         scenario[:backtrace],
        controller_action: scenario[:controller_action],
        request_path:      scenario[:request_path],
        request_method:    scenario[:request_method],
        occurred_at:       occurred,
        environment:       scenario[:environment],
        server_name:       scenario[:server_name],
        request_id:        SecureRandom.uuid,
        user_id:           users.sample&.id&.to_s,
        context:           base_context
      }
    )
    total_events += 1
  end
  puts "  [closed] #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
end

# Mark closed issues
closed_scenarios.each do |scenario|
  Issue.where(
    project: project,
    exception_class: scenario[:exception_class],
    controller_action: scenario[:controller_action]
  ).find_each do |issue|
    issue.update!(status: "closed", closed_at: (scenario[:last_seen] || 3.days.ago) + 1.hour)
  end
end

# -- Ingest job failures --
job_scenarios.each do |scenario|
  first = scenario[:first_seen] || 2.days.ago

  scenario[:occurrences].times do
    occurred = rand(first..Time.current)

    Event.ingest_error(
      project: project,
      payload: {
        exception_class:   scenario[:exception_class],
        message:           scenario[:message],
        backtrace:         scenario[:backtrace],
        controller_action: scenario[:controller_action],
        request_path:      scenario[:request_path],
        request_method:    scenario[:request_method],
        occurred_at:       occurred,
        environment:       scenario[:environment],
        server_name:       scenario[:server_name],
        request_id:        SecureRandom.uuid,
        user_id:           nil,
        context:           scenario[:context] || base_context
      }
    )
    total_events += 1
  end
  puts "  [job]    #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
end

# -- Ingest frontend errors --
frontend_scenarios.each do |scenario|
  scenario[:occurrences].times do
    occurred = rand(24.hours.ago..Time.current)

    Event.ingest_error(
      project: project,
      payload: {
        exception_class:   scenario[:exception_class],
        message:           scenario[:message],
        backtrace:         scenario[:backtrace],
        controller_action: scenario[:controller_action],
        request_path:      scenario[:request_path],
        request_method:    scenario[:request_method],
        occurred_at:       occurred,
        environment:       scenario[:environment],
        server_name:       scenario[:server_name],
        request_id:        SecureRandom.uuid,
        user_id:           users.sample&.id&.to_s,
        context:           base_context,
        source:            scenario[:source]
      }
    )
    total_events += 1
  end
  puts "  [frontend] #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
end

puts "\n  Total events created: #{total_events}"
puts "  Issues created: #{Issue.where(project: project).count}"
puts "    Open:     #{Issue.where(project: project).wip.count}"
puts "    Closed:   #{Issue.where(project: project).closed.count}"
puts "    Critical: #{Issue.where(project: project, severity: 'critical').count}"
puts "    High:     #{Issue.where(project: project, severity: 'high').count}"
puts "    Medium:   #{Issue.where(project: project, severity: 'medium').count}"
puts "    Low:      #{Issue.where(project: project, severity: 'low').count}"
puts "\n  View at: http://localhost:3003/localhost/errors"
