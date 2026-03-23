# frozen_string_literal: true

class AutoFixMonitorJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  MAX_POLL_ATTEMPTS = 30 # ~1 hour of polling (2 min intervals)
  POLL_INTERVAL = 2.minutes

  # Monitors CI status on an auto-fix PR and auto-merges when tests pass.
  # Re-enqueues itself with exponential backoff until CI completes or times out.
  #
  # For dev/staging environments, can skip CI check and merge immediately
  # if the project has `auto_merge_skip_ci` enabled.
  def perform(issue_id, project_id, attempt = 0)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    issue = Issue.find(issue_id)

    unless monitorable?(issue)
      Rails.logger.info "[AutoFixMonitor] Issue ##{issue.id} not monitorable (status=#{issue.auto_fix_status})"
      return
    end

    if attempt >= MAX_POLL_ATTEMPTS
      issue.update_columns(auto_fix_status: "ci_timeout")
      Rails.logger.warn "[AutoFixMonitor] CI timeout for issue ##{issue.id} after #{attempt} attempts"
      return
    end

    owner, repo = project.github_repo_full_name.to_s.split("/", 2)
    unless owner.present? && repo.present?
      issue.update_columns(auto_fix_status: "failed", auto_fix_error: "GitHub repo not configured")
      return
    end

    token = build_token(project)
    unless token
      issue.update_columns(auto_fix_status: "failed", auto_fix_error: "No GitHub token available")
      return
    end

    api_client = Github::ApiClient.new(token)

    # For dev/staging: skip CI and merge immediately if configured
    if project.auto_merge_skip_ci?
      Rails.logger.info "[AutoFixMonitor] Skipping CI for issue ##{issue.id} (auto_merge_skip_ci enabled)"
      attempt_merge(api_client, owner, repo, issue, project)
      return
    end

    # Check CI status on the PR
    ci_status = api_client.combined_status(owner, repo, issue.auto_fix_branch)
    check_runs = api_client.check_runs_status(owner, repo, issue.auto_fix_branch)

    overall = resolve_ci_status(ci_status, check_runs)
    Rails.logger.info "[AutoFixMonitor] Issue ##{issue.id} CI status: #{overall} (attempt #{attempt})"

    case overall
    when :success
      issue.update_columns(auto_fix_status: "ci_passed")
      attempt_merge(api_client, owner, repo, issue, project)
    when :failure
      issue.update_columns(
        auto_fix_status: "ci_failed",
        auto_fix_error: "CI checks failed on #{issue.auto_fix_branch}"
      )
      Rails.logger.warn "[AutoFixMonitor] CI failed for issue ##{issue.id}"
    when :pending
      issue.update_columns(auto_fix_status: "ci_pending") if issue.auto_fix_status != "ci_pending"
      # Re-enqueue with backoff
      delay = [POLL_INTERVAL * (1 + attempt / 5), 10.minutes].min
      AutoFixMonitorJob.perform_in(delay, issue_id, project_id, attempt + 1)
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "[AutoFixMonitor] Record not found: #{e.message}"
  rescue => e
    Rails.logger.error "[AutoFixMonitor] Error for issue #{issue_id}: #{e.message}"
    begin
      issue = ActsAsTenant.without_tenant { Issue.find_by(id: issue_id) }
      issue&.update_columns(auto_fix_status: "monitor_error", auto_fix_error: e.message)
    rescue
      nil
    end
  end

  private

  def monitorable?(issue)
    return false unless %w[pr_created pr_created_review_needed ci_pending].include?(issue.auto_fix_status)
    return false unless issue.auto_fix_branch.to_s.start_with?("ai-fix/")
    true
  end

  # Combines GitHub commit status API and check runs API into a single verdict
  def resolve_ci_status(status_response, check_runs_response)
    statuses = status_response || {}
    checks = check_runs_response || {}

    # If no CI configured at all, treat as success (nothing to block)
    status_state = statuses[:state]
    check_conclusions = checks[:conclusions] || []

    has_status = status_state.present? && status_state != "pending"
    has_checks = check_conclusions.any?

    # No CI at all → success (nothing to wait for)
    if !has_status && !has_checks && statuses[:total_count].to_i == 0 && checks[:total_count].to_i == 0
      return :success
    end

    # Any failure → failure
    if status_state == "failure" || status_state == "error"
      return :failure
    end
    if check_conclusions.include?("failure") || check_conclusions.include?("timed_out") || check_conclusions.include?("cancelled")
      return :failure
    end

    # All success → success
    all_status_ok = status_state.nil? || status_state == "success"
    all_checks_ok = check_conclusions.all? { |c| %w[success neutral skipped].include?(c) }
    checks_done = checks[:in_progress_count].to_i == 0

    if all_status_ok && all_checks_ok && checks_done
      return :success
    end

    :pending
  end

  def attempt_merge(api_client, owner, repo, issue, project)
    # Undraft the PR first (auto-fix PRs are created as drafts)
    if issue.auto_fix_pr_number
      api_client.mark_pr_ready(owner, repo, issue.auto_fix_pr_number)
    end

    result = api_client.merge_pr(owner, repo, issue.auto_fix_pr_number)

    if result[:success]
      issue.update_columns(
        auto_fix_status: "merged",
        auto_fix_merged_at: Time.current
      )
      issue.close! if issue.status == "open"

      Rails.logger.info "[AutoFixMonitor] Auto-merged PR ##{issue.auto_fix_pr_number} for issue ##{issue.id}"

      notify_merge(issue, project)
    else
      issue.update_columns(
        auto_fix_status: "merge_failed",
        auto_fix_error: result[:error]
      )
      Rails.logger.error "[AutoFixMonitor] Merge failed for issue ##{issue.id}: #{result[:error]}"
    end
  end

  def notify_merge(issue, project)
    return unless project.slack_configured?

    SlackNotificationService.new(project).send_notification(
      title: "Auto-fix merged",
      text: "AI fix for *#{issue.exception_class}* in `#{issue.controller_action}` was automatically merged.\n<#{issue.auto_fix_pr_url}|View PR>",
      color: "#36a64f"
    )
  rescue => e
    Rails.logger.warn "[AutoFixMonitor] Slack notification failed: #{e.message}"
  end

  def build_token(project)
    settings = project.settings || {}
    token_manager = Github::TokenManager.new(
      project_pat: settings["github_pat"],
      installation_id: settings["github_installation_id"],
      env_pat: ENV["GITHUB_TOKEN"],
      project_app_id: settings["github_app_id"],
      project_app_pk: settings["github_app_pk"],
      env_app_id: ENV["AR_GH_APP_ID"],
      env_app_pk: Github::TokenManager.resolve_env_private_key
    )
    token_manager.get_token
  end
end
