# frozen_string_literal: true

class AutoFixCleanupJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  STALE_THRESHOLD = 2.hours

  # Marks auto-fix issues stuck in transient states as timed out.
  # Runs every 4 hours to catch jobs where Sidekiq died mid-process
  # or the monitor job stopped re-enqueuing.
  def perform
    stale_statuses = %w[creating_pr ci_pending]
    cutoff = STALE_THRESHOLD.ago

    stale_count = ActsAsTenant.without_tenant do
      Issue.where(auto_fix_status: stale_statuses)
           .where("auto_fix_attempted_at < ?", cutoff)
           .update_all(
             auto_fix_status: "ci_timeout",
             auto_fix_error: "Timed out after #{STALE_THRESHOLD.inspect} with no CI result"
           )
    end

    Rails.logger.info "[AutoFixCleanup] Marked #{stale_count} stale auto-fix issues as timed out" if stale_count > 0
  end
end
