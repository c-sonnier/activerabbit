# frozen_string_literal: true

class AutoFixBatchMergeJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 1

  # Finds all open PRs for a project and tries to merge them.
  # Triggered when auto-merge is enabled in project settings,
  # or can be run manually to catch PRs created before auto-fix existed.
  def perform(project_id)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    return unless project.auto_merge_enabled?

    settings = project.settings || {}
    issue_pr_urls = settings["issue_pr_urls"] || {}
    return if issue_pr_urls.empty?

    owner, repo = project.github_repo_full_name.to_s.split("/", 2)
    return unless owner.present? && repo.present?

    token = build_token(project)
    return unless token

    api_client = Github::ApiClient.new(token)
    merged_count = 0

    issue_pr_urls.each do |issue_id, pr_url|
      pr_number = pr_url.to_s.match(%r{/pull/(\d+)})&.[](1)&.to_i
      next unless pr_number

      issue = project.issues.find_by(id: issue_id)
      next unless issue
      next if issue.auto_fix_status == "merged"

      begin
        pr_info = api_client.get_pr_info(owner, repo, pr_number)
        next unless pr_info
        next unless pr_info[:state] == "open"
        next if pr_info[:merged]

        # Only merge PRs created by ActiveRabbit (ai-fix/ branch prefix)
        branch = pr_info[:head_branch].to_s
        unless branch.start_with?("ai-fix/")
          Rails.logger.info "[AutoFixBatchMerge] Skipping PR ##{pr_number}: not an AI branch (#{branch})"
          next
        end

        should_merge = if project.auto_merge_skip_ci?
          true
        else
          ci_ok?(api_client, owner, repo, branch)
        end

        next unless should_merge

        if pr_info[:draft]
          api_client.mark_pr_ready(owner, repo, pr_number)
          sleep 1
        end

        result = api_client.merge_pr(owner, repo, pr_number)
        if result[:success]
          issue.update_columns(
            auto_fix_status: "merged",
            auto_fix_pr_url: pr_url,
            auto_fix_pr_number: pr_number,
            auto_fix_branch: branch,
            auto_fix_merged_at: Time.current
          )
          issue.close! if issue.status == "open"
          merged_count += 1
          Rails.logger.info "[AutoFixBatchMerge] Merged PR ##{pr_number} for issue ##{issue_id}"
        else
          Rails.logger.warn "[AutoFixBatchMerge] Could not merge PR ##{pr_number}: #{result[:error]}"
        end
      rescue => e
        Rails.logger.error "[AutoFixBatchMerge] Error processing PR ##{pr_number}: #{e.message}"
      end
    end

    Rails.logger.info "[AutoFixBatchMerge] Done for project #{project.slug}: merged #{merged_count} PRs"
  end

  private

  def ci_ok?(api_client, owner, repo, branch)
    ci = api_client.combined_status(owner, repo, branch)
    checks = api_client.check_runs_status(owner, repo, branch)

    state = ci[:state]
    conclusions = checks[:conclusions] || []
    in_progress = checks[:in_progress_count].to_i

    return false if state == "failure" || state == "error"
    return false if conclusions.include?("failure") || conclusions.include?("timed_out")
    return false if in_progress > 0

    true
  end

  def build_token(project)
    settings = project.settings || {}
    Github::TokenManager.new(
      project_pat: settings["github_pat"],
      installation_id: settings["github_installation_id"],
      env_pat: ENV["GITHUB_TOKEN"],
      project_app_id: settings["github_app_id"],
      project_app_pk: settings["github_app_pk"],
      env_app_id: ENV["AR_GH_APP_ID"],
      env_app_pk: Github::TokenManager.resolve_env_private_key
    ).get_token
  end
end
