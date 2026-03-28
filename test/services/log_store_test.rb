require "test_helper"

class LogStoreTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "insert_batch creates log entries" do
    entries = [
      { level: 2, message: "Test log 1", occurred_at: Time.current, environment: "production" },
      { level: 3, message: "Test log 2", occurred_at: Time.current, environment: "production" }
    ]

    assert_difference "LogEntry.count", 2 do
      LogStore.insert_batch(@project, entries)
    end
  end

  test "insert_batch sets account_id from project" do
    entries = [{ level: 2, message: "Test", occurred_at: Time.current, environment: "production" }]
    LogStore.insert_batch(@project, entries)

    entry = LogEntry.last
    assert_equal @account.id, entry.account_id
    assert_equal @project.id, entry.project_id
  end

  test "insert_batch scrubs PII from params and context" do
    entries = [{
      level: 2,
      message: "Test",
      occurred_at: Time.current,
      params: { "email" => "user@test.com" },
      context: { "password" => "secret123" },
      environment: "production"
    }]

    LogStore.insert_batch(@project, entries)
    entry = LogEntry.last
    assert_equal "[SCRUBBED]", entry.params["email"]
    assert_equal "[SCRUBBED]", entry.context["password"]
  end

  test "search returns matching entries" do
    results = LogStore.search(@project, { level: :error }, 24.hours)
    assert results.any?
    assert results.all? { |e| e.level == 4 }
  end

  test "find_by_trace returns entries for trace_id" do
    results = LogStore.find_by_trace("tr_abc123")
    assert results.any?
    assert results.all? { |e| e.trace_id == "tr_abc123" }
  end
end
