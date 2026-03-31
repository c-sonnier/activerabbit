require "test_helper"

class LogEntryTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "valid log entry" do
    entry = LogEntry.new(
      account: @account,
      project: @project,
      level: 2,
      message: "Test log message",
      occurred_at: Time.current
    )
    assert entry.valid?
  end

  test "requires project" do
    entry = LogEntry.new(level: 2, message: "Test", occurred_at: Time.current, account: @account)
    refute entry.valid?
    assert_includes entry.errors[:project], "must exist"
  end

  test "requires message" do
    entry = LogEntry.new(project: @project, level: 2, occurred_at: Time.current, account: @account)
    refute entry.valid?
    assert_includes entry.errors[:message], "can't be blank"
  end

  test "rejects invalid level" do
    entry = LogEntry.new(project: @project, message: "Test", occurred_at: Time.current, account: @account, level: 99)
    refute entry.valid?
    assert_includes entry.errors[:level], "is not included in the list"
  end

  test "level_name returns human-readable level" do
    entry = log_entries(:error_log)
    assert_equal "error", entry.level_name
  end

  test "scope by_level filters correctly" do
    assert LogEntry.by_level(:error).where(project: @project).exists?
    refute LogEntry.by_level(:fatal).where(project: @project).exists?
  end

  test "scope recent returns entries within timeframe" do
    recent = LogEntry.recent(2.hours)
    assert_includes recent, log_entries(:default)
    refute_includes recent, log_entries(:old_log)
  end

  test "scope for_trace finds entries by trace_id" do
    entry = log_entries(:error_log)
    assert_includes LogEntry.for_trace("tr_abc123"), entry
  end

  test "scrub_pii scrubs sensitive fields" do
    result = LogEntry.scrub_pii({ "email" => "user@example.com", "name" => "Alex" })
    assert_equal "[SCRUBBED]", result["email"]
    assert_equal "Alex", result["name"]
  end
end
