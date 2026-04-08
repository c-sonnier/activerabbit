require "test_helper"

class UsagePageReplaysTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # ===========================================================================
  # Free plan — shows NOT AVAILABLE for replays and uptime
  # ===========================================================================

  test "free plan shows NOT AVAILABLE for session replay" do
    free_user = users(:free_account_owner)
    sign_in free_user
    free_account = accounts(:free_account)
    ActsAsTenant.current_tenant = free_account

    get usage_path
    assert_response :success
    assert_select "h3", text: "Session Replay"
    assert_match(/NOT AVAILABLE/, response.body)
    assert_match(/Session replay is not included in the Free plan/, response.body)
  end

  test "free plan shows NOT AVAILABLE for uptime monitoring" do
    free_user = users(:free_account_owner)
    sign_in free_user
    free_account = accounts(:free_account)
    ActsAsTenant.current_tenant = free_account

    get usage_path
    assert_response :success
    assert_match(/Uptime monitoring is not included in the Free plan/, response.body)
  end

  test "free plan shows NOT AVAILABLE for AI summaries" do
    free_user = users(:free_account_owner)
    sign_in free_user
    free_account = accounts(:free_account)
    ActsAsTenant.current_tenant = free_account

    get usage_path
    assert_response :success
    assert_match(/AI-powered error analysis is not included in the Free plan/, response.body)
  end

  # ===========================================================================
  # Team plan — shows UNLIMITED for AI, quota for replays/uptime
  # ===========================================================================

  test "team plan shows UNLIMITED for AI summaries" do
    @account.update!(current_plan: "team")

    get usage_path
    assert_response :success
    assert_match(/UNLIMITED/, response.body)
    assert_match(/AI Error Analysis/, response.body)
  end

  test "team plan shows session replay quota of 10" do
    @account.update!(current_plan: "team", cached_replays_used: 3)

    get usage_path
    assert_response :success
    # Should show quota and usage, not NOT AVAILABLE
    refute_match(/Session replay is not included/, response.body)
  end

  test "team plan shows uptime monitors quota of 3" do
    @account.update!(current_plan: "team")

    get usage_path
    assert_response :success
    refute_match(/Uptime monitoring is not included/, response.body)
  end

  test "usage page shows logs storage card" do
    get usage_path
    assert_response :success
    assert_select "h3", text: "Logs"
    assert_match(/Storage used/, response.body)
  end
end
