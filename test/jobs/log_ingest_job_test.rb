require "test_helper"

class LogIngestJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "inserts log entries from raw payloads" do
    entries = [
      { "level" => 2, "message" => "Test log 1", "occurred_at" => Time.current.iso8601, "environment" => "production" },
      { "level" => 4, "message" => "Error log", "occurred_at" => Time.current.iso8601, "environment" => "production" }
    ]

    assert_difference "LogEntry.count", 2 do
      LogIngestJob.new.perform(@project.id, entries)
    end
  end

  test "skips if project not found" do
    assert_nothing_raised do
      LogIngestJob.new.perform(-1, [{ "message" => "test" }])
    end
  end

  test "does not insert when log storage quota is exceeded" do
    @account.update!(cached_log_bytes_used: ResourceQuotas::LOG_BYTES_QUOTA)

    entries = [
      { "message" => "should not persist", "environment" => "production" }
    ]

    assert_no_difference "LogEntry.count" do
      LogIngestJob.new.perform(@project.id, entries)
    end
  ensure
    @account.update!(cached_log_bytes_used: 0)
  end

  test "increments cached_log_bytes_used by approximate batch payload size" do
    @account.update!(cached_log_bytes_used: 0)

    entries = [
      { "message" => "hello", "environment" => "production" }
    ]
    batch_bytes = entries.sum { |e| e.to_json.bytesize }

    LogIngestJob.new.perform(@project.id, entries)

    @account.reload
    assert_operator @account.cached_log_bytes_used, :>=, batch_bytes
  ensure
    @account.update!(cached_log_bytes_used: 0)
  end
end
