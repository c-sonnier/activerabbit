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
    },
    {
      exception_class: "ActiveRecord::RecordInvalid",
      message: "Validation failed: Email has already been taken",
      backtrace: [
        "app/models/user.rb:12:in `create!'",
        "app/controllers/registrations_controller.rb:25:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "RegistrationsController#create",
      request_path: "/signup",
      request_method: "POST",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "NameError",
      message: "uninitialized constant Api::V2::UsersController",
      backtrace: [
        "actionpack (8.0.2.1) lib/action_dispatch/routing/route_set.rb:834:in `const_get'",
        "actionpack (8.0.2.1) lib/action_dispatch/routing/route_set.rb:834:in `controller_reference'",
        "actionpack (8.0.2.1) lib/action_dispatch/routing/route_set.rb:817:in `controller'"
      ],
      controller_action: "Api::V2::UsersController#index",
      request_path: "/api/v2/users",
      request_method: "GET",
      environment: "production",
      server_name: "api-02"
    },
    {
      exception_class: "ZeroDivisionError",
      message: "divided by 0",
      backtrace: [
        "app/services/analytics_service.rb:45:in `calculate_conversion_rate'",
        "app/controllers/analytics_controller.rb:18:in `dashboard'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "AnalyticsController#dashboard",
      request_path: "/analytics",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "Net::ReadTimeout",
      message: "Net::ReadTimeout with #<TCPSocket:(closed)>",
      backtrace: [
        "app/services/payment_gateway.rb:32:in `process_payment'",
        "app/controllers/checkout_controller.rb:42:in `process_payment'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "CheckoutController#process_payment",
      request_path: "/checkout/payment",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "ActiveRecord::StatementInvalid",
      message: "PG::UndefinedColumn: ERROR: column users.invalid_column does not exist",
      backtrace: [
        "app/models/user.rb:28:in `find_by_email'",
        "app/controllers/sessions_controller.rb:15:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "SessionsController#create",
      request_path: "/login",
      request_method: "POST",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActionController::RoutingError",
      message: "No route matches [GET] \"/api/v1/nonexistent\"",
      backtrace: [
        "actionpack (8.0.2.1) lib/action_dispatch/middleware/show_exceptions.rb:33:in `call'",
        "actionpack (8.0.2.1) lib/action_dispatch/middleware/debug_exceptions.rb:28:in `call'"
      ],
      controller_action: "ApplicationController#not_found",
      request_path: "/api/v1/nonexistent",
      request_method: "GET",
      environment: "production",
      server_name: "api-01"
    },
    {
      exception_class: "JSON::ParserError",
      message: "unexpected token at 'invalid json'",
      backtrace: [
        "app/controllers/api/v1/webhooks_controller.rb:18:in `parse_payload'",
        "app/controllers/api/v1/webhooks_controller.rb:8:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::WebhooksController#create",
      request_path: "/api/v1/webhooks",
      request_method: "POST",
      environment: "production",
      server_name: "api-01"
    },
    {
      exception_class: "PG::ConnectionBad",
      message: "could not connect to server: Connection refused",
      backtrace: [
        "app/models/application_record.rb:15:in `connection'",
        "app/models/user.rb:42:in `find_active_users'",
        "app/controllers/admin/users_controller.rb:12:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Admin::UsersController#index",
      request_path: "/admin/users",
      request_method: "GET",
      environment: "production",
      server_name: "web-03"
    },
    {
      exception_class: "ActionController::InvalidAuthenticityToken",
      message: "ActionController::InvalidAuthenticityToken",
      backtrace: [
        "actionpack (8.0.2.1) lib/action_controller/metal/request_forgery_protection.rb:229:in `handle_unverified_request'",
        "app/controllers/application_controller.rb:12:in `verify_authenticity_token'"
      ],
      controller_action: "OrdersController#create",
      request_path: "/orders",
      request_method: "POST",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActiveRecord::RecordNotUnique",
      message: "PG::UniqueViolation: ERROR: duplicate key value violates unique constraint",
      backtrace: [
        "app/models/invitation.rb:18:in `create!'",
        "app/controllers/invitations_controller.rb:25:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "InvitationsController#create",
      request_path: "/invitations",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "Errno::ECONNREFUSED",
      message: "Connection refused - connect(2) for \"localhost\" port 5432",
      backtrace: [
        "app/services/database_backup_service.rb:28:in `backup'",
        "app/jobs/backup_job.rb:12:in `perform'",
        "sidekiq (7.0.0) lib/sidekiq/job_executor.rb:30:in `execute'"
      ],
      controller_action: "BackupJob#perform",
      request_path: nil,
      request_method: nil,
      environment: "production",
      server_name: "worker-01"
    },
    {
      exception_class: "ActionView::MissingTemplate",
      message: "Missing template orders/show.html.erb",
      backtrace: [
        "actionview (8.0.2.1) lib/action_view/path_set.rb:48:in `find'",
        "actionview (8.0.2.1) lib/action_view/lookup_context.rb:116:in `find'",
        "app/controllers/orders_controller.rb:42:in `show'"
      ],
      controller_action: "OrdersController#show",
      request_path: "/orders/12345",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "Stripe::CardError",
      message: "Your card was declined.",
      backtrace: [
        "app/services/stripe_service.rb:45:in `charge_card'",
        "app/controllers/subscriptions_controller.rb:28:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "SubscriptionsController#create",
      request_path: "/subscriptions",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "Faraday::ConnectionFailed",
      message: "Connection refused - connect(2) for \"api.external-service.com\" port 443",
      backtrace: [
        "app/services/external_api_service.rb:52:in `make_request'",
        "app/controllers/integrations_controller.rb:35:in `sync'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "IntegrationsController#sync",
      request_path: "/integrations/sync",
      request_method: "POST",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActiveRecord::ConnectionTimeoutError",
      message: "could not obtain a connection from the pool within 5.000 seconds",
      backtrace: [
        "app/models/application_record.rb:15:in `connection'",
        "app/models/report.rb:28:in `generate'",
        "app/controllers/reports_controller.rb:18:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "ReportsController#create",
      request_path: "/reports",
      request_method: "POST",
      environment: "production",
      server_name: "web-03"
    },
    {
      exception_class: "RangeError",
      message: "bignum too big to convert into `long'",
      backtrace: [
        "app/services/calculation_service.rb:78:in `calculate_total'",
        "app/controllers/invoices_controller.rb:42:in `show'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "InvoicesController#show",
      request_path: "/invoices/999999",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActionController::UnknownFormat",
      message: "ActionController::UnknownFormat",
      backtrace: [
        "actionpack (8.0.2.1) lib/action_controller/metal/mime_responds.rb:218:in `respond_to'",
        "app/controllers/api/v1/posts_controller.rb:15:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::PostsController#index",
      request_path: "/api/v1/posts.xml",
      request_method: "GET",
      environment: "production",
      server_name: "api-01"
    },
    {
      exception_class: "Encoding::UndefinedConversionError",
      message: "\xE2\x80\x9C from UTF-8 to ASCII-8BIT",
      backtrace: [
        "app/services/file_upload_service.rb:34:in `process_file'",
        "app/controllers/uploads_controller.rb:28:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "UploadsController#create",
      request_path: "/uploads",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "SystemStackError",
      message: "stack level too deep",
      backtrace: [
        "app/models/user.rb:156:in `calculate_score'",
        "app/models/user.rb:156:in `calculate_score'",
        "app/models/user.rb:156:in `calculate_score'"
      ],
      controller_action: "UsersController#show",
      request_path: "/users/123",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActiveRecord::Deadlocked",
      message: "deadlock detected",
      backtrace: [
        "app/models/transaction.rb:45:in `process'",
        "app/controllers/transactions_controller.rb:28:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "TransactionsController#create",
      request_path: "/transactions",
      request_method: "POST",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "JWT::DecodeError",
      message: "Not enough or too many segments",
      backtrace: [
        "app/services/auth_service.rb:28:in `decode_token'",
        "app/controllers/api/v1/base_controller.rb:15:in `authenticate_user'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::UsersController#index",
      request_path: "/api/v1/users",
      request_method: "GET",
      environment: "production",
      server_name: "api-01"
    },
    {
      exception_class: "OpenSSL::SSL::SSLError",
      message: "SSL_connect returned=1 errno=0 state=error: certificate verify failed",
      backtrace: [
        "app/services/secure_api_client.rb:42:in `make_secure_request'",
        "app/controllers/payments_controller.rb:35:in `process'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "PaymentsController#process",
      request_path: "/payments/process",
      request_method: "POST",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "ActiveRecord::SerializationFailure",
      message: "could not serialize access due to concurrent update",
      backtrace: [
        "app/models/account.rb:78:in `update_balance'",
        "app/controllers/accounts_controller.rb:42:in `update'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "AccountsController#update",
      request_path: "/accounts/123",
      request_method: "PATCH",
      environment: "production",
      server_name: "web-02"
    },
    {
      exception_class: "LoadError",
      message: "cannot load such file -- missing_gem",
      backtrace: [
        "app/services/legacy_service.rb:5:in `require'",
        "app/controllers/legacy_controller.rb:12:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "LegacyController#index",
      request_path: "/legacy",
      request_method: "GET",
      environment: "production",
      server_name: "web-01"
    },
    {
      exception_class: "SocketError",
      message: "getaddrinfo: nodename nor servname provided, or not known",
      backtrace: [
        "app/services/dns_lookup_service.rb:18:in `resolve'",
        "app/controllers/admin/diagnostics_controller.rb:25:in `check_dns'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Admin::DiagnosticsController#check_dns",
      request_path: "/admin/diagnostics/dns",
      request_method: "GET",
      environment: "production",
      server_name: "web-03"
    }
  ].freeze

  desc "Add sample errors for a project (slug, e.g. acme-web). Each error type gets a random count from 1 to max_per_type (default 100)."
  task :for_project, [:slug, :max_per_type] => :environment do |_t, args|
    slug = args[:slug] || "acme-web"
    total_events = (args[:max_per_type] || 100).to_i  # max events per error type (1..total_events)

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

      # Each error type gets a random count from 1 to 100 (or use total_events as max per type if given)
      max_per_type = total_events.positive? ? [total_events, 100].min : 100
      min_per_type = 1

      puts "Seeding #{SAMPLE_ERRORS.size} error types with random counts (#{min_per_type}–#{max_per_type} events per type)..."
      puts "Spread over: #{period_start.to_date} .. #{period_end.to_date}"
      puts

      SAMPLE_ERRORS.each_with_index do |scenario, idx|
        count_for_type = rand(min_per_type..max_per_type)
        count_for_type.times do
          occurred_at = Time.at(period_start + (period_end - period_start) * rand)

          payload = scenario.merge(
            occurred_at: occurred_at,
            request_id: SecureRandom.uuid,
            user_id: "user-#{rand(1..100)}",
            context: { "ruby_version" => "3.4.8", "rails_version" => "8.0.2.1" }
          )

          Event.ingest_error(project: project, payload: payload)
          created += 1
          print "." if (created % 50).zero?
        end
      end

      puts
      puts "Created #{created} events (#{project.issues.reload.count} issues for this project)."
      puts "View errors: http://localhost:3003/#{slug}/errors?period=30d"
    ensure
      ActsAsTenant.current_tenant = nil
    end
  end
end
