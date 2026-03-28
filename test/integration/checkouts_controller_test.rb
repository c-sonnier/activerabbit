require "test_helper"

class CheckoutsControllerTest < ActionDispatch::IntegrationTest
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

  test "requires authentication" do
    sign_out @user
    post checkouts_path, params: { plan: "starter" }
    assert_redirected_to new_user_session_path
  end

  test "POST create with free plan updates account" do
    post checkouts_path, params: { plan: "free" }

    assert_redirected_to dashboard_path
    @account.reload
    assert_equal "free", @account.current_plan
  end

  test "POST create with free plan sets success message" do
    post checkouts_path, params: { plan: "free" }

    assert_redirected_to dashboard_path
    assert flash[:notice].present?
  end

  test "POST create with paid plan requires Stripe checkout" do
    # Stub CheckoutCreator to return a mock checkout session
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")

    CheckoutCreator.stub(:new, ->(**args) {
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "starter", interval: "month" }

      # Should redirect to Stripe checkout
      assert_response :see_other
    end
  end

  test "POST create with interval parameter" do
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")
    interval_passed = nil

    CheckoutCreator.stub(:new, ->(**args) {
      interval_passed = args[:interval]
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "starter", interval: "year" }
    end

    assert_equal "year", interval_passed
  end

  test "POST create with ai parameter" do
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")
    ai_passed = nil

    CheckoutCreator.stub(:new, ->(**args) {
      ai_passed = args[:ai]
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "starter", ai: "true" }
    end

    assert ai_passed.present?
  end

  test "POST create handles errors gracefully" do
    CheckoutCreator.stub(:new, ->(**args) {
      raise StandardError, "Stripe error"
    }) do
      post checkouts_path, params: { plan: "starter" }

      assert_redirected_to settings_path
      assert flash[:alert].present?
    end
  end

  test "POST create passes addon params to CheckoutCreator" do
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")
    params_received = {}

    CheckoutCreator.stub(:new, ->(**args) {
      params_received = args
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: {
        plan: "team",
        interval: "month",
        uptime_monitors: "10",
        extra_errors: "200000",
        session_replays: "5000"
      }
    end

    assert_equal "10", params_received[:uptime_monitors]
    assert_equal "200000", params_received[:extra_errors]
    assert_equal "5000", params_received[:session_replays]
  end

  test "POST create passes ai param with addons" do
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test")
    params_received = {}

    CheckoutCreator.stub(:new, ->(**args) {
      params_received = args
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: {
        plan: "team",
        interval: "month",
        ai: "1",
        uptime_monitors: "5",
        extra_errors: "0",
        session_replays: "0"
      }
    end

    assert_equal "1", params_received[:ai]
    assert_equal "5", params_received[:uptime_monitors]
  end
end
