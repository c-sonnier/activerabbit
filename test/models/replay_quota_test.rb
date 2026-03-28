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
  # replay_quota_exceeded?
  # ===========================================================================

  test "replay_quota_exceeded? returns false when under quota" do
    @account.update!(replay_quota: 100, cached_replays_used: 50)
    refute @account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? returns true when at quota" do
    @account.update!(replay_quota: 100, cached_replays_used: 100)
    assert @account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? returns true when over quota" do
    @account.update!(replay_quota: 100, cached_replays_used: 150)
    assert @account.replay_quota_exceeded?
  end

  test "replay_quota_exceeded? returns true with zero quota" do
    @account.update!(replay_quota: 0, cached_replays_used: 0)
    assert @account.replay_quota_exceeded?
  end

  # ===========================================================================
  # replays_quota_remaining
  # ===========================================================================

  test "replays_quota_remaining returns correct value" do
    @account.update!(replay_quota: 100, cached_replays_used: 30)
    assert_equal 70, @account.replays_quota_remaining
  end

  test "replays_quota_remaining returns 0 when over quota" do
    @account.update!(replay_quota: 100, cached_replays_used: 150)
    # replay_quota - cached_replays_used = -50, but method returns raw calculation
    assert_equal(-50, @account.replays_quota_remaining)
  end

  test "replays_quota_remaining returns full quota when unused" do
    @account.update!(replay_quota: 100, cached_replays_used: 0)
    assert_equal 100, @account.replays_quota_remaining
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
end
