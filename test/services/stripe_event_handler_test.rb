require "test_helper"

class StripeEventHandlerTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    # Create a Pay::Customer if Pay is available
    @pay_customer = Pay::Customer.create!(owner: @account, processor: "stripe", processor_id: "cus_123")
  end

  test "sets past_due on payment_failed" do
    failed_event = {
      "type" => "invoice.payment_failed",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "in_1"
        }
      }
    }

    StripeEventHandler.new(event: failed_event).call
    assert @account.reload.settings["past_due"]
  end

  test "clears past_due on payment_succeeded" do
    # First set past_due
    @account.update!(settings: { "past_due" => true })

    succeeded_event = {
      "type" => "invoice.payment_succeeded",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "in_2"
        }
      }
    }

    StripeEventHandler.new(event: succeeded_event).call
    assert_nil @account.reload.settings["past_due"]
  end

  # ============================================================================
  # Usage reset on plan upgrade
  # ============================================================================

  test "resets usage counters when upgrading from free to team" do
    @account.update!(
      current_plan: "free",
      trial_ends_at: 1.month.ago,
      cached_events_used: 4_500,
      cached_performance_events_used: 100,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    # Temporarily set the env var for the test
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_upgrade_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal "team", @account.current_plan
    assert_equal 0, @account.cached_events_used, "Events used should be reset on upgrade"
    assert_equal 0, @account.cached_performance_events_used, "Perf events should be reset"
    assert_equal 0, @account.cached_ai_summaries_used, "AI summaries should be reset"
    assert_equal 0, @account.cached_pull_requests_used, "PRs should be reset"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "resets usage counters when upgrading from trial to team" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 1.day.from_now,
      cached_events_used: 2_000,
      cached_ai_summaries_used: 10,
      cached_pull_requests_used: 5
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_upgrade_2",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal "team", @account.current_plan
    assert_equal 0, @account.cached_events_used, "Events should be reset on trial->team"
    assert_equal 0, @account.cached_ai_summaries_used, "AI summaries should be reset"
    assert_equal 0, @account.cached_pull_requests_used, "PRs should be reset"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "does NOT reset usage counters when plan stays the same (team->team renewal)" do
    @account.update!(
      current_plan: "team",
      cached_events_used: 30_000,
      cached_ai_summaries_used: 12
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_renewal_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal "team", @account.current_plan
    assert_equal 30_000, @account.cached_events_used, "Events should NOT be reset on same-plan renewal"
    assert_equal 12, @account.cached_ai_summaries_used, "AI summaries should NOT be reset"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Welcome email on plan upgrade
  # ============================================================================

  test "sends welcome email when upgrading from free to team" do
    @account.update!(
      current_plan: "free",
      trial_ends_at: 1.month.ago,
      cached_events_used: 1_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_welcome_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    email_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_later, true)

    LifecycleMailer.stub(:plan_upgraded, ->(**args) {
      email_sent = true
      assert_equal @account, args[:account]
      assert_equal "team", args[:new_plan]
      mock_mail
    }) do
      StripeEventHandler.new(event: subscription_event).call
    end

    assert email_sent, "Should send welcome email on plan upgrade"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Incomplete subscription should NOT upgrade plan
  # ============================================================================

  test "does NOT upgrade plan when subscription is incomplete" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_events_used: 1_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_incomplete_1",
          "status" => "incomplete",
          "trial_end" => nil,
          "current_period_start" => nil,
          "current_period_end" => nil,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal "trial", @account.current_plan, "Plan should remain trial when subscription is incomplete"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "does NOT upgrade plan when subscription is past_due" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_past_due_1",
          "status" => "past_due",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal "trial", @account.current_plan, "Plan should remain trial when subscription is past_due"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "DOES upgrade plan when subscription is active" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_events_used: 1_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_active_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal "team", @account.current_plan, "Plan should be upgraded to team when subscription is active"
    assert_equal 0, @account.cached_events_used, "Usage counters should be reset on upgrade"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "still creates Pay::Subscription record for incomplete subscriptions" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_incomplete_track",
          "status" => "incomplete",
          "trial_end" => nil,
          "current_period_start" => nil,
          "current_period_end" => nil,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call

    pay_sub = Pay::Subscription.find_by(processor_id: "sub_incomplete_track")
    assert pay_sub.present?, "Pay::Subscription record should be created even for incomplete subscriptions"
    assert_equal "incomplete", pay_sub.status
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Welcome email (existing tests)
  # ============================================================================

  test "does NOT send welcome email on same-plan renewal" do
    @account.update!(
      current_plan: "team",
      cached_events_used: 10_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_renewal_2",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    email_sent = false
    LifecycleMailer.stub(:plan_upgraded, ->(**args) {
      email_sent = true
      flunk "Should NOT send welcome email on same-plan renewal"
    }) do
      StripeEventHandler.new(event: subscription_event).call
    end

    refute email_sent, "Welcome email should NOT be sent on same-plan renewal"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Addon quota updates from subscription items
  # ============================================================================

  test "sets addon_uptime_monitors from subscription items" do
    @account.update!(current_plan: "free", trial_ends_at: 1.month.ago)

    original_team = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    original_uptime = ENV["STRIPE_PRICE_UPTIME_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = "price_uptime_m"

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_addon_uptime_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => "price_team_m" }, "quantity" => 1 },
              { "price" => { "id" => "price_uptime_m" }, "quantity" => 2 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal 10, @account.addon_uptime_monitors, "2 packs x 5 = 10 uptime monitors"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_team
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = original_uptime
  end

  test "sets addon_extra_errors from subscription items" do
    @account.update!(current_plan: "free", trial_ends_at: 1.month.ago)

    original_team = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    original_errors = ENV["STRIPE_PRICE_ERRORS_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_ERRORS_MONTHLY"] = "price_errors_m"

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_addon_errors_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => "price_team_m" }, "quantity" => 1 },
              { "price" => { "id" => "price_errors_m" }, "quantity" => 3 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal 300_000, @account.addon_extra_errors, "3 packs x 100K = 300K extra errors"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_team
    ENV["STRIPE_PRICE_ERRORS_MONTHLY"] = original_errors
  end

  test "sets addon_session_replays from subscription items" do
    @account.update!(current_plan: "free", trial_ends_at: 1.month.ago)

    original_team = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    original_replays = ENV["STRIPE_PRICE_REPLAYS_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_REPLAYS_MONTHLY"] = "price_replays_m"

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_addon_replays_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => "price_team_m" }, "quantity" => 1 },
              { "price" => { "id" => "price_replays_m" }, "quantity" => 2 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal 10_000, @account.addon_session_replays, "2 packs x 5K = 10K session replays"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_team
    ENV["STRIPE_PRICE_REPLAYS_MONTHLY"] = original_replays
  end

  test "sets all addons from a single subscription with multiple items" do
    @account.update!(current_plan: "free", trial_ends_at: 1.month.ago)

    original_team = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    original_uptime = ENV["STRIPE_PRICE_UPTIME_MONTHLY"]
    original_errors = ENV["STRIPE_PRICE_ERRORS_MONTHLY"]
    original_replays = ENV["STRIPE_PRICE_REPLAYS_MONTHLY"]
    original_ai = ENV["STRIPE_PRICE_AI_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = "price_uptime_m"
    ENV["STRIPE_PRICE_ERRORS_MONTHLY"] = "price_errors_m"
    ENV["STRIPE_PRICE_REPLAYS_MONTHLY"] = "price_replays_m"
    ENV["STRIPE_PRICE_AI_MONTHLY"] = "price_ai_m"

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_addon_all_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => "price_team_m" }, "quantity" => 1 },
              { "price" => { "id" => "price_uptime_m" }, "quantity" => 2 },
              { "price" => { "id" => "price_errors_m" }, "quantity" => 3 },
              { "price" => { "id" => "price_replays_m" }, "quantity" => 2 },
              { "price" => { "id" => "price_ai_m" }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal 10, @account.addon_uptime_monitors, "2 packs x 5 = 10 uptime monitors"
    assert_equal 300_000, @account.addon_extra_errors, "3 packs x 100K = 300K extra errors"
    assert_equal 10_000, @account.addon_session_replays, "2 packs x 5K = 10K session replays"
    assert @account.ai_mode_enabled, "AI mode should be enabled when AI addon is present"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_team
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = original_uptime
    ENV["STRIPE_PRICE_ERRORS_MONTHLY"] = original_errors
    ENV["STRIPE_PRICE_REPLAYS_MONTHLY"] = original_replays
    ENV["STRIPE_PRICE_AI_MONTHLY"] = original_ai
  end

  test "resets addon columns to zero when addons removed from subscription" do
    @account.update!(current_plan: "team", addon_uptime_monitors: 10)

    original_team = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_addon_reset_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => "price_team_m" }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal 0, @account.addon_uptime_monitors, "Uptime monitors should be reset to 0"
    assert_equal 0, @account.addon_extra_errors, "Extra errors should be reset to 0"
    assert_equal 0, @account.addon_session_replays, "Session replays should be reset to 0"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_team
  end

  test "updates addon quantities when subscription is updated" do
    @account.update!(current_plan: "team", addon_uptime_monitors: 5)

    original_team = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    original_uptime = ENV["STRIPE_PRICE_UPTIME_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = "price_team_m"
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = "price_uptime_m"

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_addon_update_1",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => "price_team_m" }, "quantity" => 1 },
              { "price" => { "id" => "price_uptime_m" }, "quantity" => 4 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    @account.reload

    assert_equal 20, @account.addon_uptime_monitors, "4 packs x 5 = 20 uptime monitors"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_team
    ENV["STRIPE_PRICE_UPTIME_MONTHLY"] = original_uptime
  end
end
