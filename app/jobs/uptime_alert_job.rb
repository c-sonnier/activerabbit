# frozen_string_literal: true

class UptimeAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
  URL_PROTOCOL = Rails.env.production? ? "https" : "http"
  RATE_LIMIT_TTL = 5.minutes.to_i

  def perform(monitor_id, alert_type, payload = {})
    monitor = ActsAsTenant.without_tenant { UptimeMonitor.find_by(id: monitor_id) }
    return unless monitor

    # Rate limit: one alert per monitor per type per 5 minutes
    lock_key = "uptime_alert:#{monitor.id}:#{alert_type}"
    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: RATE_LIMIT_TTL, nx: true) }
    return unless lock_acquired

    account = monitor.account
    project = monitor.project

    ActsAsTenant.with_tenant(account) do
      # Email: always send to confirmed account users (no project required)
      send_email_alert(account, project, monitor, alert_type, payload)

      # Slack: use project-level if available, otherwise account-level
      if project&.notify_via_slack?
        send_slack_alert(project, monitor, alert_type, payload)
      elsif account.slack_notifications_enabled?
        send_account_slack_alert(account, monitor, alert_type, payload)
      end

      # Discord: requires project-level config
      if project&.notify_via_discord?
        send_discord_alert(project, monitor, alert_type, payload)
      end
    end
  end

  private

  # --- Slack ---

  def send_slack_alert(project, monitor, alert_type, payload)
    service = SlackNotificationService.new(project)
    service.send_uptime_alert(monitor, alert_type, payload)
  rescue => e
    Rails.logger.error("[UptimeAlert] Slack (project) failed: #{e.message}")
  end

  def send_account_slack_alert(account, monitor, alert_type, payload)
    webhook_url = account.settings&.dig("slack_webhook_url")
    return unless webhook_url.present?

    emoji = alert_type == "up" ? ":white_check_mark:" : ":red_circle:"
    status_text = alert_type == "up" ? "RECOVERED" : "DOWN"

    text = "#{emoji} *Uptime #{status_text}: #{monitor.name}*\n"
    text += "URL: #{monitor.url}\n"
    text += "Status: #{status_text}\n"
    if alert_type == "down" && payload["consecutive_failures"]
      text += "Consecutive Failures: #{payload['consecutive_failures']}\n"
    end
    text += "Response Time: #{monitor.last_response_time_ms || 'N/A'}ms\n"
    text += "<#{monitor_url(monitor)}|View Monitor>"

    Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { text: text }.to_json
    end
  rescue => e
    Rails.logger.error("[UptimeAlert] Slack (account webhook) failed: #{e.message}")
  end

  # --- Discord ---

  def send_discord_alert(project, monitor, alert_type, payload)
    service = DiscordNotificationService.new(project)
    service.send_uptime_alert(monitor, alert_type, payload)
  rescue => e
    Rails.logger.error("[UptimeAlert] Discord failed: #{e.message}")
  end

  # --- Email ---

  def send_email_alert(account, project, monitor, alert_type, payload)
    subject_action = alert_type == "up" ? "Monitor Recovered" : "Monitor Down"
    project_prefix = project ? "#{project.name}: " : ""
    subject = "#{project_prefix}#{subject_action} - #{monitor.name}"
    body = build_email_body(monitor, alert_type, payload)

    confirmed_users = account.users.select(&:email_confirmed?)
    return if confirmed_users.empty?

    confirmed_users.each_with_index do |user, index|
      sleep(0.6) if index > 0
      AlertMailer.send_alert(
        to: user.email,
        subject: subject,
        body: body,
        project: project || OpenStruct.new(name: account.name),
        dashboard_url: monitor_url(monitor)
      ).deliver_now
    end
  rescue => e
    Rails.logger.error("[UptimeAlert] Email failed: #{e.message}")
  end

  def build_email_body(monitor, alert_type, payload)
    if alert_type == "down"
      <<~EMAIL
        UPTIME ALERT - MONITOR DOWN

        Monitor: #{monitor.name}
        URL: #{monitor.url}
        Status: DOWN
        Consecutive Failures: #{payload['consecutive_failures']}
        Last Status Code: #{monitor.last_status_code || 'N/A'}

        This monitor has failed #{payload['consecutive_failures']} consecutive checks.
      EMAIL
    elsif alert_type == "ssl_expiry"
      <<~EMAIL
        SSL CERTIFICATE EXPIRY WARNING

        Monitor: #{monitor.name}
        URL: #{monitor.url}
        SSL Expires In: #{payload['days_until_expiry']} days
        Expiry Date: #{payload['ssl_expiry']}

        Please renew the SSL certificate before it expires.
      EMAIL
    else
      <<~EMAIL
        UPTIME RECOVERY - MONITOR UP

        Monitor: #{monitor.name}
        URL: #{monitor.url}
        Status: UP (recovered)
        Response Time: #{monitor.last_response_time_ms}ms

        This monitor has recovered and is responding normally.
      EMAIL
    end
  end

  def monitor_url(monitor)
    "#{URL_PROTOCOL}://#{URL_HOST}/uptime/#{monitor.id}"
  end
end
