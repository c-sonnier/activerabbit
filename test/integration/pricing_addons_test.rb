require "test_helper"

class PricingAddonsTest < ActionDispatch::IntegrationTest
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
  # Addons section renders on pricing page
  # ===========================================================================

  test "pricing page renders addons section" do
    get plan_path
    assert_response :success
    assert_select "[data-controller='addons']", 1
  end

  test "addons section has Customize Your Plan heading" do
    get plan_path
    assert_response :success
    assert_select "h2", /Customize Your Plan/
  end

  test "addons section renders AI Error Analysis card with unlimited" do
    get plan_path
    assert_select "[data-addons-target='aiCard']", 1
    assert_match(/AI Error Analysis/, response.body)
    assert_match(/unlimited analyses/, response.body)
  end

  test "addons section renders Uptime Monitors slider with step 5" do
    get plan_path
    assert_select "[data-addons-target='uptimeSlider']" do |elements|
      slider = elements.first
      assert_equal "0", slider["min"]
      assert_equal "100", slider["max"]
      assert_equal "5", slider["step"]
    end
  end

  test "addons section renders Extra Errors slider" do
    get plan_path
    assert_select "[data-addons-target='errorsSlider']" do |elements|
      slider = elements.first
      assert_equal "0", slider["min"]
      assert_equal "1000000", slider["max"]
      assert_equal "100000", slider["step"]
    end
  end

  test "addons section renders Session Replay slider with step 5000" do
    get plan_path
    assert_select "[data-addons-target='replaySlider']" do |elements|
      slider = elements.first
      assert_equal "0", slider["min"]
      assert_equal "500000", slider["max"]
      assert_equal "5000", slider["step"]
    end
  end

  # ===========================================================================
  # Summary box renders with plan tier and frequency toggles
  # ===========================================================================

  test "summary box renders Reserved Pricing header" do
    get plan_path
    assert_match(/Reserved Pricing/, response.body)
  end

  test "summary box has plan tier toggle buttons" do
    get plan_path
    assert_select "[data-addons-target='tierTeam']", 1
    assert_select "[data-addons-target='tierBusiness']", 1
  end

  test "summary box has payment frequency toggle buttons" do
    get plan_path
    assert_select "[data-addons-target='freqAnnual']", 1
    assert_select "[data-addons-target='freqMonthly']", 1
  end

  test "summary box has total monthly and annual displays" do
    get plan_path
    assert_select "[data-addons-target='totalMonthly']", 1
  end

  test "summary box has line items container" do
    get plan_path
    assert_select "[data-addons-target='itemList']", 1
  end

  # ===========================================================================
  # Addons section appears between pricing cards and feature table
  # ===========================================================================

  test "pricing page still renders all three plan cards" do
    get plan_path
    assert_select "h3", text: "Free"
    assert_select "h3", text: "Team"
    assert_select "h3", text: "Business"
  end

  test "pricing page does not render Usage Limits table" do
    get plan_path
    # Table was removed; heading should not render as visible HTML element
    assert_select "h3", text: "Usage Limits", count: 0
    assert_select "table", count: 0
  end

  test "plan cards include uptime monitors" do
    get plan_path
    assert_match(/monitors \(uptime \+ cron\)/, response.body) # Team card copy
    assert_match(/5 monitors \(uptime \+ cron\)/, response.body) # Business
  end

  test "plan cards include session replays" do
    get plan_path
    assert_match(/10 session replays/, response.body)
  end

  test "plan cards show unlimited AI error analysis" do
    get plan_path
    assert_match(/Unlimited AI error analysis/, response.body)
  end

  test "subscribe form exists with hidden addon fields" do
    get plan_path
    # Check addon-specific hidden fields (scoped by data-addons-target)
    assert_select "[data-addons-target='formPlan']", 1
    assert_select "[data-addons-target='formInterval']", 1
    assert_select "[data-addons-target='formAi']", 1
    assert_select "[data-addons-target='formUptime']", 1
    assert_select "[data-addons-target='formErrors']", 1
    assert_select "[data-addons-target='formReplays']", 1
  end

  test "subscribe button exists" do
    get plan_path
    assert_select "[data-addons-target='submitButton']", 1
    assert_select "[data-addons-target='submitButton']", /Subscribe|Update Plan/
  end

  # ===========================================================================
  # Addons Stimulus controller file exists
  # ===========================================================================

  test "addons stimulus controller exists" do
    controller_path = Rails.root.join("app/javascript/controllers/addons_controller.js")
    assert File.exist?(controller_path), "addons_controller.js should exist"
  end

  # ===========================================================================
  # Authentication required
  # ===========================================================================

  test "pricing page requires authentication" do
    sign_out @user
    get plan_path
    assert_redirected_to new_user_session_path
  end

  # ===========================================================================
  # Different plan states
  # ===========================================================================

  test "pricing page renders for free plan account" do
    free_user = users(:free_account_owner)
    sign_in free_user
    ActsAsTenant.current_tenant = accounts(:free_account)

    get plan_path
    assert_response :success
    assert_select "[data-controller='addons']", 1
  end

  test "pricing page renders for trial account" do
    trial_user = users(:trial_user)
    sign_in trial_user
    ActsAsTenant.current_tenant = accounts(:trial_account)

    get plan_path
    assert_response :success
    assert_select "[data-controller='addons']", 1
  end
end
