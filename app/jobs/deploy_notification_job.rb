class DeployNotificationJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
  URL_PROTOCOL = Rails.env.production? ? "https" : "http"

  def perform(deploy_id, phase)
    deploy = ActsAsTenant.without_tenant do
      Deploy.includes(:user, :release, :project).find_by(id: deploy_id)
    end
    return unless deploy

    project = deploy.project
    account = project.account

    ActsAsTenant.with_tenant(account) do
      case phase
      when "started"
        return unless project.notify_deploy_started?
      when "finished"
        return unless project.notify_deploy_finished?
      else
        return
      end

      if project.notify_via_slack?
        slack_service = SlackNotificationService.new(project)
        if slack_service.configured?
          slack_service.send_deploy_notification(deploy, phase: phase)
        elsif account.slack_webhook_url.present? && account.settings&.dig("slack_notifications_enabled") != false
          send_account_slack_deploy(account, project, deploy, phase)
        end
      end

      if project.notify_via_discord?
        discord_service = DiscordNotificationService.new(project)
        discord_service.send_deploy_notification(deploy, phase: phase) if discord_service.configured?
      end
    end
  end

  private

  def send_account_slack_deploy(account, project, deploy, phase)
    webhook_url = account.slack_webhook_url
    return unless webhook_url.present?

    title = phase == "started" ? ":rocket: Deployment in progress" : ":white_check_mark: Deployment completed"
    lines = [
      "*#{title}*",
      "*Project:* #{project.name}",
      "*Version:* #{deploy.release.version}",
      "*Environment:* #{deploy.release.environment}"
    ]
    if deploy.user
      lines << "*By:* #{deploy.user.try(:name).presence || deploy.user.email}"
    end
    lines << "*Started:* #{deploy.started_at.utc.strftime('%Y-%m-%d %H:%M UTC')}"
    if deploy.finished_at.present?
      lines << "*Finished:* #{deploy.finished_at.utc.strftime('%Y-%m-%d %H:%M UTC')}"
      secs = (deploy.finished_at - deploy.started_at).to_i
      lines << "*Duration:* #{secs}s" if secs.positive?
    end
    lines << "*Status:* #{deploy.status}" if deploy.status.present?
    lines << "<#{deploys_page_url(project)}|View deploys>"

    Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { text: lines.join("\n") }.to_json
    end
  rescue StandardError => e
    Rails.logger.error("[DeployNotificationJob] Slack (account webhook) failed: #{e.message}")
  end

  def deploys_page_url(project)
    "#{URL_PROTOCOL}://#{URL_HOST}/#{project.slug}/deploys"
  end
end
