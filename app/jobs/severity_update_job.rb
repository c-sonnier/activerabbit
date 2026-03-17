# frozen_string_literal: true

# Recalculates severity for all active (open/wip) issues.
# Run periodically (every 5-10 minutes) to keep severity badges accurate.
#
# Severity uses a multi-factor scoring algorithm (0-100 points):
#   - Event frequency (24h)   – up to 25 pts
#   - Total event count        – up to 10 pts
#   - Unique users affected    – up to 20 pts
#   - Velocity (spike detect)  – up to 15 pts
#   - Exception type severity  – up to 15 pts
#   - Recurrence (reopened)    – up to 10 pts
#   - Freshness (new errors)   – up to  5 pts
#
# Score thresholds: critical >= 60, high >= 35, medium >= 15, low < 15
#
class SeverityUpdateJob < ApplicationJob
  queue_as :default

  def perform
    updated = 0
    Account.find_each do |account|
      ActsAsTenant.with_tenant(account) do
        updated += update_severities_for_account
      end
    end
    Rails.logger.info("[SeverityUpdateJob] Finished: #{updated} issues updated")
  end

  private

  def update_severities_for_account
    updated = 0
    Issue.where(status: %w[open wip]).find_each do |issue|
      new_severity = issue.calculated_severity
      if issue.severity != new_severity
        old = issue.severity
        issue.update_column(:severity, new_severity)
        Rails.logger.info("[SeverityUpdateJob] Issue ##{issue.id}: #{old} -> #{new_severity} (score=#{issue.severity_score})")
        updated += 1
      end
    end
    updated
  end
end
