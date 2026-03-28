require "test_helper"

class CheckoutCreatorTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @user = users(:owner)

    # Set required ENV variables
    ENV["STRIPE_PRICE_DEV_MONTHLY"] = "price_dev_m"
    ENV["STRIPE_PRICE_DEV_ANNUAL"] = "price_dev_y"
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_TEAM_ANNUAL"] = "price_team_y"
    ENV["STRIPE_PRICE_ENT_MONTHLY"] = "price_ent_m"
    ENV["STRIPE_PRICE_ENT_ANNUAL"] = "price_ent_y"
    ENV["STRIPE_PRICE_AI_MONTHLY"] = "price_ai_m"
    ENV["STRIPE_PRICE_AI_ANNUAL"] = "price_ai_y"
    ENV["STRIPE_PRICE_AI_OVERAGE_METERED"] = "price_ai_over_m"
    ENV["APP_HOST"] = "localhost:3000"

    # Stub Stripe
    stub_request(:post, /api\.stripe\.com/).to_return(
      status: 200,
      body: { url: "https://stripe.example/session" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  test "creates checkout creator with required params" do
    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      ai: false
    )

    assert creator.is_a?(CheckoutCreator)
  end

  test "creates checkout creator with addon params" do
    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      ai: true,
      uptime_monitors: 15,
      extra_errors: 200_000,
      session_replays: 10_000
    )

    assert creator.is_a?(CheckoutCreator)
  end

  test "addon params default to zero" do
    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month"
    )

    assert creator.is_a?(CheckoutCreator)
  end

  test "build_line_items includes uptime addon when monitors > 0" do
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = "price_uptime_m"

    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      uptime_monitors: 15
    )

    line_items = creator.send(:build_line_items)
    uptime_item = line_items.find { |i| i[:price] == "price_uptime_m" }

    assert_not_nil uptime_item
    assert_equal 3, uptime_item[:quantity] # ceil(15/5) = 3 packs
  end

  test "build_line_items includes errors addon when errors > 0" do
    ENV["STRIPE_PRICE_ERRORS_MONTHLY"] = "price_errors_m"

    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      extra_errors: 200_000
    )

    line_items = creator.send(:build_line_items)
    errors_item = line_items.find { |i| i[:price] == "price_errors_m" }

    assert_not_nil errors_item
    assert_equal 2, errors_item[:quantity] # ceil(200K/100K) = 2 packs
  end

  test "build_line_items includes replays addon when replays > 0" do
    ENV["STRIPE_PRICE_REPLAYS_MONTHLY"] = "price_replays_m"

    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      session_replays: 10_000
    )

    line_items = creator.send(:build_line_items)
    replays_item = line_items.find { |i| i[:price] == "price_replays_m" }

    assert_not_nil replays_item
    assert_equal 2, replays_item[:quantity] # ceil(10K/5K) = 2 packs
  end

  test "build_line_items excludes addons when values are zero" do
    creator = CheckoutCreator.new(
      user: @user,
      account: @account,
      plan: "team",
      interval: "month",
      uptime_monitors: 0,
      extra_errors: 0,
      session_replays: 0
    )

    line_items = creator.send(:build_line_items)
    # Only the base plan price
    assert_equal 1, line_items.length
  end
end
