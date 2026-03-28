# frozen_string_literal: true

require "ostruct"

module CheckIns
  class AlertJob
    include Sidekiq::Job

    sidekiq_options queue: :alerts, retry: 3

    URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
    URL_PROTOCOL = Rails.env.production? ? "https" : "http"
    RATE_LIMIT_TTL = 30.minutes.to_i

    def perform(check_in_id)
      check_in = ActsAsTenant.without_tenant { ::CheckIn.find_by(id: check_in_id) }
      return unless check_in

      lock_key = "check_in_alert:#{check_in.id}"
      lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: RATE_LIMIT_TTL, nx: true) }
      return unless lock_acquired

      account = check_in.account
      project = check_in.project

      ActsAsTenant.with_tenant(account) do
        send_email_alert(account, project, check_in)

        if project&.notify_via_slack?
          send_slack_alert(project, check_in)
        elsif account.slack_notifications_enabled?
          send_account_slack_alert(account, check_in)
        end

        if project&.notify_via_discord?
          send_discord_alert(project, check_in)
        end
      end
    end

    private

    def send_slack_alert(project, check_in)
      service = SlackNotificationService.new(project)
      service.send_check_in_alert(check_in)
    rescue => e
      Rails.logger.error("[CheckIn::AlertJob] Slack (project) failed: #{e.message}")
    end

    def send_account_slack_alert(account, check_in)
      webhook_url = account.settings&.dig("slack_webhook_url")
      return unless webhook_url.present?

      text = ":warning: *Missed Check-In: #{check_in.description || check_in.identifier}*\n"
      text += "Project: #{check_in.project.name}\n"
      text += "Expected every: #{check_in.interval_display}\n"
      text += "Last seen: #{check_in.last_seen_at&.strftime('%b %d, %H:%M UTC') || 'Never'}\n"
      text += "<#{check_in_url(check_in)}|View Check-In>"

      Faraday.post(webhook_url) do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = { text: text }.to_json
      end
    rescue => e
      Rails.logger.error("[CheckIn::AlertJob] Slack (account webhook) failed: #{e.message}")
    end

    def send_discord_alert(project, check_in)
      service = DiscordNotificationService.new(project)
      service.send_check_in_alert(check_in)
    rescue => e
      Rails.logger.error("[CheckIn::AlertJob] Discord failed: #{e.message}")
    end

    def send_email_alert(account, project, check_in)
      subject = "Missed Check-In: #{check_in.description || check_in.identifier}"
      body = build_email_body(check_in)

      confirmed_users = account.users.select(&:email_confirmed?)
      return if confirmed_users.empty?

      confirmed_users.each_with_index do |user, index|
        sleep(0.6) if index > 0
        AlertMailer.send_alert(
          to: user.email,
          subject: subject,
          body: body,
          project: project || OpenStruct.new(name: account.name),
          dashboard_url: check_in_url(check_in)
        ).deliver_now
      end
    rescue => e
      Rails.logger.error("[CheckIn::AlertJob] Email failed: #{e.message}")
    end

    def build_email_body(check_in)
      <<~EMAIL
        MISSED CHECK-IN ALERT

        Name: #{check_in.description || check_in.identifier}
        Project: #{check_in.project.name}
        Expected Interval: #{check_in.interval_display}
        Last Seen: #{check_in.last_seen_at&.strftime('%b %d, %Y at %H:%M UTC') || 'Never'}

        This check-in has not reported within its expected interval.
        Your cron job or scheduled task may have stopped running.
      EMAIL
    end

    def check_in_url(check_in)
      "#{URL_PROTOCOL}://#{URL_HOST}/check_ins/#{check_in.id}"
    end
  end
end
