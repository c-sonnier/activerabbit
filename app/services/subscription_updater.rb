class SubscriptionUpdater
  Result = Struct.new(:success)

  def initialize(account:, plan:, interval:, ai: false, uptime_monitors: 0, extra_errors: 0, session_replays: 0)
    @account = account
    @plan = plan
    @interval = interval
    @ai = ActiveModel::Type::Boolean.new.cast(ai)
    @uptime_monitors = uptime_monitors.to_i
    @extra_errors = extra_errors.to_i
    @session_replays = session_replays.to_i
  end

  def call
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"] if Stripe.api_key.nil? || Stripe.api_key.to_s.strip.empty?

    pay_sub = @account.active_subscription_record
    raise "No active subscription found" unless pay_sub

    stripe_sub = Stripe::Subscription.retrieve(pay_sub.processor_id)

    # Build the desired set of items
    new_items = build_subscription_items(stripe_sub)

    Stripe::Subscription.update(
      pay_sub.processor_id,
      items: new_items,
      metadata: {
        account_id: @account.id,
        plan: @plan,
        interval: @interval,
        ai: @ai,
        uptime_monitors: @uptime_monitors,
        extra_errors: @extra_errors,
        session_replays: @session_replays
      },
      proration_behavior: "create_prorations"
    )

    Result.new(true)
  end

  private

  def build_subscription_items(stripe_sub)
    existing_items = stripe_sub.items.data
    items = []

    # Delete all existing items and add new ones
    existing_items.each do |item|
      items << { id: item.id, deleted: true }
    end

    # Add base plan
    items << { price: price_for_plan(@plan, @interval), quantity: 1 }

    # Add AI
    if @ai
      items << { price: ai_base_price, quantity: 1 }
      if ENV["STRIPE_PRICE_AI_OVERAGE_METERED"].present?
        items << { price: ENV["STRIPE_PRICE_AI_OVERAGE_METERED"] }
      end
    end

    # Add uptime monitors
    if @uptime_monitors > 0
      qty = (@uptime_monitors / 5.0).ceil
      items << { price: uptime_price, quantity: qty }
    end

    # Add extra errors
    if @extra_errors > 0
      qty = (@extra_errors / 100_000.0).ceil
      items << { price: errors_price, quantity: qty }
    end

    # Add session replays
    if @session_replays > 0
      qty = (@session_replays / 5_000.0).ceil
      items << { price: replays_price, quantity: qty }
    end

    items
  end

  def price_for_plan(plan, interval)
    case [plan, interval]
    when ["team", "month"]      then ENV.fetch("STRIPE_PRICE_TEAM_MONTHLY")
    when ["team", "year"]       then ENV.fetch("STRIPE_PRICE_TEAM_ANNUAL", ENV["STRIPE_PRICE_TEAM_MONTHLY"])
    when ["business", "month"]  then ENV.fetch("STRIPE_PRICE_BUSINESS_MONTHLY")
    when ["business", "year"]   then ENV.fetch("STRIPE_PRICE_BUSINESS_ANNUAL", ENV["STRIPE_PRICE_BUSINESS_MONTHLY"])
    else raise ArgumentError, "unknown plan/interval: #{plan}/#{interval}"
    end
  end

  def ai_base_price
    @interval == "year" ? ENV.fetch("STRIPE_PRICE_AI_ANNUAL") : ENV.fetch("STRIPE_PRICE_AI_MONTHLY")
  end

  def uptime_price
    @interval == "year" ? ENV.fetch("STRIPE_PRICE_UPTIME_ANNUAL", ENV["STRIPE_PRICE_UPTIME_MONTHLY"]) : ENV.fetch("STRIPE_PRICE_UPTIME_MONTHLY")
  end

  def errors_price
    @interval == "year" ? ENV.fetch("STRIPE_PRICE_ERRORS_ANNUAL", ENV["STRIPE_PRICE_ERRORS_MONTHLY"]) : ENV.fetch("STRIPE_PRICE_ERRORS_MONTHLY")
  end

  def replays_price
    @interval == "year" ? ENV.fetch("STRIPE_PRICE_REPLAYS_ANNUAL", ENV["STRIPE_PRICE_REPLAYS_MONTHLY"]) : ENV.fetch("STRIPE_PRICE_REPLAYS_MONTHLY")
  end
end
