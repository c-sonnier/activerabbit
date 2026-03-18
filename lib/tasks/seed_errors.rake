# frozen_string_literal: true

namespace :seed_errors do
  # Sample error payloads (exception_class, message, backtrace, controller_action, etc.)
  SAMPLE_ERRORS = [
    {
      exception_class: "ActiveRecord::RecordNotFound",
      message: "Couldn't find User with 'id'=99942",
      backtrace: [
        "app/controllers/users_controller.rb:14:in `show'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'",
        "actionpack (8.0.2.1) lib/abstract_controller/base.rb:226:in `process_action'"
      ],
      controller_action: "UsersController#show",
      request_path: "/users/99942",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActionController::ParameterMissing",
      message: "param is missing or the value is empty: order",
      backtrace: [
        "app/controllers/orders_controller.rb:42:in `order_params'",
        "app/controllers/orders_controller.rb:18:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "OrdersController#create",
      request_path: "/orders",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "NoMethodError",
      message: "undefined method `name' for nil:NilClass",
      backtrace: [
        "app/views/dashboard/index.html.erb:23:in `_app_views_dashboard_index_html_erb__1234'",
        "actionview (8.0.2.1) lib/action_view/template.rb:278:in `block in render'",
        "activesupport (8.0.2.1) lib/active_support/notifications.rb:212:in `instrument'"
      ],
      controller_action: "DashboardController#index",
      request_path: "/dashboard",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "Timeout::Error",
      message: "execution expired",
      backtrace: [
        "app/services/external_api_client.rb:55:in `fetch_recommendations'",
        "app/controllers/products_controller.rb:30:in `show'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "ProductsController#show",
      request_path: "/products/fancy-widget",
      request_method: "GET",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "Redis::TimeoutError",
      message: "Connection timed out after 5.0 seconds",
      backtrace: [
        "app/services/cache_service.rb:18:in `fetch_user_preferences'",
        "app/controllers/settings_controller.rb:8:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "SettingsController#index",
      request_path: "/settings",
      request_method: "GET",
      environment: "production",
      server_name: "web-03"
    },
    {
      exception_class: "TypeError",
      message: "no implicit conversion of nil into String",
      backtrace: [
        "app/services/csv_exporter.rb:42:in `generate_row'",
        "app/services/csv_exporter.rb:18:in `block in export'",
        "app/controllers/exports_controller.rb:11:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "ExportsController#create",
      request_path: "/exports",
      request_method: "POST",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "RuntimeError",
      message: "Stripe webhook signature verification failed",
      backtrace: [
        "app/controllers/webhooks/stripe_controller.rb:15:in `verify_signature!'",
        "app/controllers/webhooks/stripe_controller.rb:5:in `create'",
        "actionpack (8.0.2.1) lib/action_dispatch/middleware/executor.rb:14:in `call'"
      ],
      controller_action: "Webhooks::StripeController#create",
      request_path: "/webhooks/stripe",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "ArgumentError",
      message: "invalid date: '2025-13-45'",
      backtrace: [
        "app/controllers/api/v1/reports_controller.rb:28:in `parse_date_range'",
        "app/controllers/api/v1/reports_controller.rb:8:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::ReportsController#index",
      request_path: "/api/v1/reports?start=2025-13-45",
      request_method: "GET",
      environment: "production",
      server_name: "api-01"
    }
  ].freeze

  desc "Add sample errors for a project (slug, e.g. acme-web). Spreads events over the last 30 days."
  task :for_project, [:slug, :count] => :environment do |_t, args|
    slug = args[:slug] || "acme-web"
    total_events = (args[:count] || 80).to_i

    # Find project without tenant scope (rake has no current_tenant)
    project = ActsAsTenant.without_tenant { Project.find_by(slug: slug) }
    unless project
      puts "Project with slug '#{slug}' not found."
      puts "Available projects: #{ActsAsTenant.without_tenant { Project.pluck(:slug).join(', ') }}"
      exit 1
    end

    # Set tenant for Event/Issue creation (same pattern as ErrorIngestJob)
    ActsAsTenant.current_tenant = project.account
    begin
      period_start = 30.days.ago
      period_end = Time.current
      created = 0

      puts "Adding up to #{total_events} error events for project '#{project.name}' (#{slug})..."
      puts "Spread over: #{period_start.to_date} .. #{period_end.to_date}"
      puts

      total_events.times do |i|
        scenario = SAMPLE_ERRORS[i % SAMPLE_ERRORS.size]
        occurred_at = Time.at(period_start + (period_end - period_start) * rand)

        payload = scenario.merge(
          occurred_at: occurred_at,
          request_id: SecureRandom.uuid,
          user_id: "user-#{rand(1..100)}",
          context: { "ruby_version" => "3.4.8", "rails_version" => "8.0.2.1" }
        )

        Event.ingest_error(project: project, payload: payload)
        created += 1
        print "." if (created % 10).zero?
      end

      puts
      puts "Created #{created} events (#{project.issues.reload.count} issues for this project)."
      puts "View errors: http://localhost:3003/#{slug}/errors?period=30d"
    ensure
      ActsAsTenant.current_tenant = nil
    end
  end
end
