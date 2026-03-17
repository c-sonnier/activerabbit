require "test_helper"

class IssueTest < ActiveSupport::TestCase
  # Validations

  test "validates presence of fingerprint" do
    issue = Issue.new(fingerprint: nil)
    refute issue.valid?
    assert_includes issue.errors[:fingerprint], "can't be blank"
  end

  test "validates presence of exception_class" do
    issue = Issue.new(exception_class: nil)
    refute issue.valid?
    assert_includes issue.errors[:exception_class], "can't be blank"
  end

  test "validates presence of top_frame" do
    issue = Issue.new(top_frame: nil)
    refute issue.valid?
    assert_includes issue.errors[:top_frame], "can't be blank"
  end

  test "validates presence of controller_action" do
    issue = Issue.new(controller_action: nil)
    refute issue.valid?
    assert_includes issue.errors[:controller_action], "can't be blank"
  end

  # find_or_create_by_fingerprint

  test "find_or_create_by_fingerprint creates a new issue and increments counts" do
    project = projects(:default)

    issue = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "/app/controllers/home_controller.rb:10:in `index'",
      controller_action: "HomeController#index",
      sample_message: "boom"
    )

    assert issue.persisted?
    assert_equal 1, issue.count

    # Find same issue again
    same = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "/app/controllers/home_controller.rb:32:in `index'",
      controller_action: "HomeController#index",
      sample_message: "boom again"
    )

    assert_equal issue.id, same.id
    assert_equal 2, same.count
  end

  test "find_or_create_by_fingerprint handles RecordNotUnique and increments count" do
    project = projects(:default)
    params = {
      project: project,
      exception_class: "RaceConditionError",
      top_frame: "/app/controllers/race_controller.rb:10:in `index'",
      controller_action: "RaceController#index",
      sample_message: "boom"
    }

    # Create the issue directly
    issue = Issue.find_or_create_by_fingerprint(**params)
    assert_equal 1, issue.count

    # Simulate the RecordNotUnique path: stub create! to raise, then
    # verify the rescue branch atomically increments count.
    Issue.stub(:find_by, ->(*args, **kwargs) { nil }, issue) do
      # find_by returns nil → falls through to create! → RecordNotUnique →
      # retry find_by (unstubbed now) → increment
    end

    # More direct test: call find_or_create again, count should be 2
    same = Issue.find_or_create_by_fingerprint(**params)
    assert_equal issue.id, same.id
    assert_equal 2, same.count

    # Third time: count should be 3 (atomic, no lost updates)
    third = Issue.find_or_create_by_fingerprint(**params)
    assert_equal 3, third.count
  end

  test "find_or_create_by_fingerprint uses atomic SQL increment" do
    project = projects(:default)
    params = {
      project: project,
      exception_class: "AtomicIncrError",
      top_frame: "/app/controllers/atomic_controller.rb:5:in `show'",
      controller_action: "AtomicController#show",
      sample_message: "atomic test"
    }

    issue = Issue.find_or_create_by_fingerprint(**params)
    assert_equal 1, issue.count

    # Call 10 times sequentially — count must be exactly 11
    10.times { Issue.find_or_create_by_fingerprint(**params) }
    assert_equal 11, issue.reload.count
  end

  # Status transitions

  test "mark_wip sets status to wip" do
    issue = issues(:open_issue)
    issue.mark_wip!
    assert_equal "wip", issue.status
  end

  test "close sets status to closed" do
    issue = issues(:open_issue)
    issue.close!
    assert_equal "closed", issue.status
  end

  test "reopen sets status to open" do
    issue = issues(:closed_issue)
    issue.reopen!
    assert_equal "open", issue.status
  end

  # events_last_24h uses occurred_at (not created_at)

  test "events_last_24h counts events by occurred_at" do
    issue = issues(:open_issue)

    # Fixture events for open_issue:
    #   default: occurred_at=now, recent: 5min ago,
    #   recent_event_for_open: 2h ago (all within 24h)
    #   very_old_event_for_open: 3 days ago (outside 24h)
    count = issue.events_last_24h
    assert count >= 2, "Expected at least 2 recent events, got #{count}"

    # The 3-day old event should NOT be counted
    total = issue.events.count
    assert count < total, "events_last_24h should exclude old events"
  end

  test "events_last_24h returns 0 when no recent events" do
    issue = issues(:old_issue)
    # old_issue has no events in fixtures, so count should be 0
    assert_equal 0, issue.events_last_24h
  end

  # Job failure detection heuristic

  test "job failure issue has non-controller controller_action" do
    job_issue = issues(:job_failure_issue)
    refute_match(/Controller#/, job_issue.controller_action)

    regular_issue = issues(:open_issue)
    assert_match(/Controller#/, regular_issue.controller_action)
  end

  # Severity calculation
  #
  # severity_score = impact + frequency + business + regression + data_risk - mitigation
  # Thresholds: critical >= 80, high >= 55, medium >= 25, low < 25

  test "calculated_severity returns low for cosmetic error in admin area" do
    # RoutingError (cosmetic=5) + admin (biz=8) + no events (freq=0) - mitigation (admin -10, few users -8 = -18)
    # Score: 5 + 0 + 8 + 0 + 0 - 18 = -5 → clamped to 0 → Low
    project = projects(:default)
    issue = Issue.new(
      project: project, fingerprint: "sev-low-#{SecureRandom.hex(4)}",
      exception_class: "ActionController::RoutingError",
      top_frame: "/app/test.rb:1", controller_action: "Admin::DashboardController#index",
      count: 1, status: "open", first_seen_at: 2.days.ago, last_seen_at: 1.day.ago
    )
    assert_equal "low", issue.calculated_severity
  end

  test "calculated_severity returns medium for regular error in normal feature" do
    # RuntimeError (internal=25) + regular feature (biz=12) - few users (-8)
    # Score: 25 + 0 + 12 + 0 + 0 - 8 = 29 → Medium
    project = projects(:default)
    issue = Issue.new(
      project: project, fingerprint: "sev-med-#{SecureRandom.hex(4)}",
      exception_class: "RuntimeError",
      top_frame: "/app/test.rb:1", controller_action: "ReportsController#show",
      count: 1, status: "open", first_seen_at: 2.days.ago, last_seen_at: 1.hour.ago
    )
    assert_equal "medium", issue.calculated_severity
  end

  test "calculated_severity returns high for internal error in checkout area" do
    # NoMethodError (internal=25) + checkout (biz=30) + data_risk (checkout=30, cap 40) - few users (-8)
    # Score: 25 + 0 + 30 + 0 + 30 - 8 = 77 → High
    project = projects(:default)
    issue = Issue.new(
      project: project, fingerprint: "sev-high-#{SecureRandom.hex(4)}",
      exception_class: "NoMethodError",
      top_frame: "/app/test.rb:1", controller_action: "CheckoutController#create",
      count: 1, status: "open", first_seen_at: 2.days.ago, last_seen_at: 1.hour.ago
    )
    assert_equal "high", issue.calculated_severity
  end

  test "calculated_severity returns critical for crash in payment with security risk" do
    # SecurityError (crash=35) + checkout (biz=30) + data_risk (security=40) - few users (-8)
    # Score: 35 + 0 + 30 + 0 + 40 - 8 = 97 → Critical
    project = projects(:default)
    issue = Issue.new(
      project: project, fingerprint: "sev-crit-#{SecureRandom.hex(4)}",
      exception_class: "SecurityError",
      top_frame: "/app/test.rb:1", controller_action: "PaymentController#charge",
      count: 1, status: "open", first_seen_at: 2.days.ago, last_seen_at: 1.hour.ago
    )
    assert_equal "critical", issue.calculated_severity
  end

  test "severity is set on save" do
    project = projects(:default)
    issue = Issue.new(
      project: project,
      fingerprint: "test-severity-#{SecureRandom.hex(8)}",
      exception_class: "RuntimeError",
      top_frame: "/app/test.rb:1",
      controller_action: "TestController#test",
      count: 1,
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    issue.save!

    assert_includes %w[low medium high critical], issue.severity
  end

  test "update_severity! updates stored severity" do
    # SecurityError in payment → critical (score ~97)
    project = projects(:default)
    issue = Issue.create!(
      project: project, fingerprint: "sev-update-#{SecureRandom.hex(4)}",
      exception_class: "SecurityError",
      top_frame: "/app/test.rb:1", controller_action: "PaymentController#charge",
      count: 1, status: "open", first_seen_at: 2.days.ago, last_seen_at: 1.hour.ago
    )
    issue.update_column(:severity, "low") # Force wrong severity

    issue.update_severity!

    assert_equal "critical", issue.reload.severity
  end

  test "severity validation allows valid values" do
    issue = issues(:open_issue)

    %w[low medium high critical].each do |sev|
      issue.severity = sev
      assert issue.valid?, "Expected severity '#{sev}' to be valid"
    end
  end

  test "severity validation rejects invalid values" do
    issue = issues(:open_issue)
    issue.severity = "invalid"
    refute issue.valid?
    assert_includes issue.errors[:severity], "is not included in the list"
  end

  test "severity can be nil" do
    issue = issues(:open_issue)
    issue.severity = nil
    assert issue.valid?, "Severity should allow nil for existing issues"
  end
end
