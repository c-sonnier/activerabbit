require "test_helper"

class ReplayQuotaTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # ===========================================================================
  # session_replays_quota (plan-based)
  # ===========================================================================

  test "session_replays_quota returns 0 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 0, account.session_replays_quota
  end

  test "session_replays_quota returns 10 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 10, account.session_replays_quota
  end

  test "session_replays_quota returns correct value for team plan" do
    account = Account.new(current_plan: "team")
    expected = Rails.env.production? ? 10 : 50
    assert_equal expected, account.session_replays_quota
  end

  test "session_replays_quota returns 10 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 10, account.session_replays_quota
  end

  # ===========================================================================
  # replay_quota_exceeded? (now plan-based)
  # ===========================================================================

  test "replay_quota_exceeded? returns false when under plan quota" do
    account = Account.new(current_plan: "team", cached_replays_used: 5)
    refute account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? returns true when at plan quota" do
    quota = Account.new(current_plan: "team").session_replays_quota
    account = Account.new(current_plan: "team", cached_replays_used: quota)
    assert account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? returns true when over plan quota" do
    quota = Account.new(current_plan: "team").session_replays_quota
    account = Account.new(current_plan: "team", cached_replays_used: quota + 5)
    assert account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? returns true for free plan even with zero usage" do
    account = Account.new(current_plan: "free", cached_replays_used: 0)
    assert account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? handles nil cached_replays_used" do
    account = Account.new(current_plan: "team", cached_replays_used: nil)
    refute account.replay_quota_exceeded?
  end

  # ===========================================================================
  # replays_quota_remaining
  # ===========================================================================

  test "replays_quota_remaining returns correct value for team plan" do
    quota = Account.new(current_plan: "team").session_replays_quota
    account = Account.new(current_plan: "team", cached_replays_used: 3)
    assert_equal quota - 3, account.replays_quota_remaining
  end

  test "replays_quota_remaining returns negative when over quota" do
    quota = Account.new(current_plan: "team").session_replays_quota
    account = Account.new(current_plan: "team", cached_replays_used: quota + 5)
    assert_equal(-5, account.replays_quota_remaining)
  end

  test "replays_quota_remaining returns full quota when unused" do
    quota = Account.new(current_plan: "team").session_replays_quota
    account = Account.new(current_plan: "team", cached_replays_used: 0)
    assert_equal quota, account.replays_quota_remaining
  end

  test "replays_quota_remaining returns 0 for free plan" do
    account = Account.new(current_plan: "free", cached_replays_used: 0)
    assert_equal 0, account.replays_quota_remaining
  end

  # ===========================================================================
  # increment_replay_usage!
  # ===========================================================================

  test "increment_replay_usage! increments by 1" do
    @account.update!(cached_replays_used: 5)
    @account.increment_replay_usage!
    assert_equal 6, @account.reload.cached_replays_used
  end

  test "increment_replay_usage! works from zero" do
    @account.update!(cached_replays_used: 0)
    @account.increment_replay_usage!
    assert_equal 1, @account.reload.cached_replays_used
  end

  test "increment_replay_usage! persists to database" do
    @account.update!(cached_replays_used: 10)
    @account.increment_replay_usage!
    fresh = Account.find(@account.id)
    assert_equal 11, fresh.cached_replays_used
  end

  # ===========================================================================
  # session_replays in usage_summary
  # ===========================================================================

  test "usage_summary includes session_replays" do
    @account.current_plan = "team"
    @account.trial_ends_at = nil
    @account.cached_replays_used = 3
    @account.instance_variable_set(:@_usage_summary, nil)
    summary = @account.usage_summary

    assert summary.key?(:session_replays)
    quota = Account.new(current_plan: "team").session_replays_quota
    assert_equal quota, summary[:session_replays][:quota]
    assert_equal 3, summary[:session_replays][:used]
    assert_equal quota - 3, summary[:session_replays][:remaining]
    assert summary[:session_replays][:within_quota]
  end

  test "usage_summary session_replays shows over quota correctly" do
    @account.current_plan = "team"
    @account.cached_replays_used = 12
    summary = @account.usage_summary

    assert_equal 0, summary[:session_replays][:remaining]
    refute summary[:session_replays][:within_quota]
  end
end
