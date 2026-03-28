require "test_helper"

class LogArchiveJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "deletes expired log entries" do
    old_entry = log_entries(:old_log)
    assert old_entry.occurred_at < @account.data_retention_cutoff

    assert_difference "LogEntry.count", -1 do
      LogArchiveJob.new.perform
    end
  end

  test "does not delete recent log entries" do
    recent_entry = log_entries(:default)
    LogArchiveJob.new.perform
    assert LogEntry.exists?(recent_entry.id)
  end
end
