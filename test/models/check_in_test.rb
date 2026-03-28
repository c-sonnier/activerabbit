# frozen_string_literal: true

require "test_helper"

class CheckInTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "generates identifier on create" do
    ci = CheckIn.create!(
      project: @project,
      account: @account,
      description: "Minimal check-in",
      kind: "cron",
      heartbeat_interval_seconds: 600,
      timezone: "UTC",
      enabled: true
    )
    assert ci.identifier.present?
    assert_equal 20, ci.identifier.length
  end

  test "assigns slug from description on create when slug omitted" do
    ci = CheckIn.create!(
      project: @project,
      account: @account,
      description: "Daily Backup",
      kind: "cron",
      heartbeat_interval_seconds: 600,
      timezone: "UTC",
      enabled: true
    )
    assert_equal "daily_backup", ci.slug
  end

  test "status_display new when never seen" do
    ci = check_ins(:new_unused)
    assert_equal "new", ci.status_display
  end

  test "status_display healthy when recent ping" do
    ci = check_ins(:healthy)
    assert_equal "healthy", ci.status_display
  end

  test "status_display missed when overdue" do
    ci = check_ins(:overdue_alert)
    assert ci.overdue?
    assert_equal "missed", ci.status_display
  end

  test "overdue? is false when disabled" do
    ci = check_ins(:disabled)
    refute ci.overdue?
  end

  test "should_alert? when overdue and not recently alerted" do
    ci = check_ins(:overdue_alert)
    assert ci.should_alert?
  end

  test "should_alert? is false when healthy" do
    ci = check_ins(:healthy)
    refute ci.should_alert?
  end

  test "ping! updates last_seen_at and last_status" do
    ci = check_ins(:new_unused)
    freeze_time do
      ci.ping!
      ci.reload
      assert_equal Time.current, ci.last_seen_at
      assert_equal "reporting", ci.last_status
    end
  end

  test "mark_alerted! sets last_alerted_at and missed" do
    ci = check_ins(:healthy)
    freeze_time do
      ci.mark_alerted!
      ci.reload
      assert_equal Time.current, ci.last_alerted_at
      assert_equal "missed", ci.last_status
    end
  end

  test "interval_display formats seconds" do
    ci = CheckIn.new(heartbeat_interval_seconds: 300)
    assert_equal "5m", ci.interval_display
  end

  test "ping_url includes token and respects APP_HOST with scheme" do
    ci = check_ins(:api_ok)
    original = ENV["APP_HOST"]
    ENV["APP_HOST"] = "https://example.com"
    assert_equal "https://example.com/api/v1/check_in/#{ci.identifier}", ci.ping_url
  ensure
    ENV["APP_HOST"] = original
  end

  test "belongs to project and has many pings" do
    assert_equal :belongs_to, CheckIn.reflect_on_association(:project).macro
    assert_equal :has_many, CheckIn.reflect_on_association(:pings).macro
  end

  test "normalizes slug with parameterize" do
    ci = CheckIn.new(
      project: @project,
      account: @account,
      kind: "cron",
      heartbeat_interval_seconds: 600,
      timezone: "UTC",
      enabled: true,
      slug: "  Daily Backup  "
    )
    ci.valid?
    assert_equal "daily_backup", ci.slug
  end

  test "record_success_ping! creates ping row" do
    ci = check_ins(:new_unused)
    ActsAsTenant.without_tenant { CheckInPing.where(check_in_id: ci.id).delete_all }

    assert_difference -> { ci.pings.count }, 1 do
      ActsAsTenant.with_tenant(@account) do
        ci.record_success_ping!(source_ip: "127.0.0.1")
      end
    end

    ci.reload
    assert_equal "reporting", ci.last_status
    assert ci.last_seen_at.present?
    assert_equal "127.0.0.1", ci.pings.last.source_ip
  end
end
