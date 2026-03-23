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

    project = monitor.project
    return unless project&.notifications_enabled?

    # Rate limit: one alert per monitor per type per 5 minutes
    lock_key = "uptime_alert:#{monitor.id}:#{alert_type}"
    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: RATE_LIMIT_TTL, nx: true) }
    return unless lock_acquired

    ActsAsTenant.with_tenant(monitor.account) do
      send_slack_alert(project, monitor, alert_type, payload) if project.notify_via_slack?
      send_discord_alert(project, monitor, alert_type, payload) if project.notify_via_discord?
      send_email_alert(project, monitor, alert_type, payload) if project.notify_via_email?
    end
  end

  private

  def send_slack_alert(project, monitor, alert_type, payload)
    service = SlackNotificationService.new(project)
    service.send_uptime_alert(monitor, alert_type, payload)
  rescue => e
    Rails.logger.error("[UptimeAlert] Slack failed: #{e.message}")
  end

  def send_discord_alert(project, monitor, alert_type, payload)
    service = DiscordNotificationService.new(project)
    service.send_uptime_alert(monitor, alert_type, payload)
  rescue => e
    Rails.logger.error("[UptimeAlert] Discord failed: #{e.message}")
  end

  def send_email_alert(project, monitor, alert_type, payload)
    subject = alert_type == "up" ? "Monitor Recovered" : "Monitor Down"
    body = build_email_body(monitor, alert_type, payload)

    confirmed_users = project.account.users.select(&:email_confirmed?)
    confirmed_users.each_with_index do |user, index|
      sleep(0.6) if index > 0
      AlertMailer.send_alert(
        to: user.email,
        subject: "#{project.name}: #{subject} - #{monitor.name}",
        body: body,
        project: project,
        dashboard_url: "#{URL_PROTOCOL}://#{URL_HOST}/uptime/#{monitor.id}"
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
end
