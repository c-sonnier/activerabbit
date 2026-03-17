# frozen_string_literal: true

# Recalculates severity for all active (open/wip) issues.
# Run periodically (every 5-10 minutes) to keep severity badges accurate.
#
# severity_score = impact + frequency + business + regression + data_risk - mitigation
#
#   A. Impact        (max ~35) — how much does it break?
#   B. Frequency     (max ~50) — events/hour + % of unique users
#   C. Business      (max ~30) — checkout/auth/core/admin/internal
#   D. Regression    (max ~25) — reappeared after fix or appeared after deploy
#   E. Data Risk     (max ~40) — security/data-loss/billing risk
#   F. Mitigation    (max -20) — auto-retry, admin-only, single user
#
# Score thresholds: critical >= 80, high >= 55, medium >= 25, low < 25
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
