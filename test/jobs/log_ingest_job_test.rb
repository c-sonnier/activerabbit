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
end
