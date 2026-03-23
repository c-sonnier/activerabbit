# frozen_string_literal: true

module Uptime
  class AlertJob
    include Sidekiq::Job

    sidekiq_options queue: :alerts, retry: 3

    URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
    URL_PROTOCOL = Rails.env.production? ? "https" : "http"
    RATE_LIMIT_TTL = 5.minutes.to_i

    def perform(monitor_id, alert_type, payload = {})
      monitor = ActsAsTenant.without_tenant { Uptime::Monitor.find_by(id: monitor_id) }
      return unless monitor

      lock_key = "uptime_alert:#{monitor.id}:#{alert_type}"
      lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: RATE_LIMIT_TTL, nx: true) }
      return unless lock_acquired

      account = monitor.account
      project = monitor.project

      if project
        uptime_prefs = project.settings&.dig("notifications", "uptime") || {}
        case alert_type
        when "down"
          return if uptime_prefs["downtime"] == false
        when "up"
          return if uptime_prefs["recovery"] == false
        when "ssl_expiry"
          return if uptime_prefs["ssl_expiry"] == false
        end
      end

      ActsAsTenant.with_tenant(account) do
        send_email_alert(account, project, monitor, alert_type, payload)

        if project&.notify_via_slack?
          send_slack_alert(project, monitor, alert_type, payload)
        elsif account.slack_notifications_enabled?
          send_account_slack_alert(account, monitor, alert_type, payload)
        end

        if project&.notify_via_discord?
          send_discord_alert(project, monitor, alert_type, payload)
        end
      end
    end

    private

    def send_slack_alert(project, monitor, alert_type, payload)
      service = SlackNotificationService.new(project)
      service.send_uptime_alert(monitor, alert_type, payload)
    rescue => e
      Rails.logger.error("[Uptime::AlertJob] Slack (project) failed: #{e.message}")
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
      Rails.logger.error("[Uptime::AlertJob] Slack (account webhook) failed: #{e.message}")
    end

    def send_discord_alert(project, monitor, alert_type, payload)
      service = DiscordNotificationService.new(project)
      service.send_uptime_alert(monitor, alert_type, payload)
    rescue => e
      Rails.logger.error("[Uptime::AlertJob] Discord failed: #{e.message}")
    end

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
      Rails.logger.error("[Uptime::AlertJob] Email failed: #{e.message}")
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
end
