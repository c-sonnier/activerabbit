class CheckoutCreator
  Result = Struct.new(:url)

  def initialize(user:, account:, plan:, interval:, ai: false, uptime_monitors: 0, extra_errors: 0, session_replays: 0)
    @user = user
    @account = account
    @plan = plan # "team"|"business"
    @interval = interval # "month"|"year"
    @ai = ActiveModel::Type::Boolean.new.cast(ai)
    @uptime_monitors = uptime_monitors.to_i
    @extra_errors = extra_errors.to_i
    @session_replays = session_replays.to_i
  end

  def call
    # Defensive: ensure API key is present even if initializers haven't set it
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"] if Stripe.api_key.nil? || Stripe.api_key.to_s.strip.empty?
    ensure_pay_customer!

    session = create_checkout_session!

    Result.new(session.url)
  end

  private

  def ensure_pay_customer!
    @user.set_payment_processor :stripe if @user.payment_processor.blank?
    if @user.payment_processor.processor_id.blank?
      recreate_stripe_customer!
    end
  end

  def recreate_stripe_customer!
    stripe_customer = Stripe::Customer.create(
      email: @user.email,
      metadata: { user_id: @user.id, account_id: @account.id }
    )
    @user.payment_processor.update!(processor_id: stripe_customer.id)
  end

  def build_line_items
    items = [{ price: price_for_plan(@plan, @interval), quantity: 1 }]
    if @ai
      items << { price: ai_base_price, quantity: 1 }
      if ENV["STRIPE_PRICE_AI_OVERAGE_METERED"].present?
        items << { price: ENV["STRIPE_PRICE_AI_OVERAGE_METERED"], quantity: 1 }
      end
    end
    if @uptime_monitors > 0
      qty = (@uptime_monitors / 5.0).ceil # packs of 5
      items << { price: uptime_price, quantity: qty }
    end
    if @extra_errors > 0
      qty = (@extra_errors / 100_000.0).ceil # packs of 100K
      items << { price: errors_price, quantity: qty }
    end
    if @session_replays > 0
      qty = (@session_replays / 5_000.0).ceil # packs of 5K
      items << { price: replays_price, quantity: qty }
    end
    items
  end

  def create_checkout_session!
    Stripe::Checkout::Session.create(
      mode: "subscription",
      customer: @user.payment_processor.processor_id,
      payment_method_collection: "if_required", # do NOT require card for free trial
      success_url: success_url,
      cancel_url: cancel_url,
      allow_promotion_codes: true,
      client_reference_id: @account.id,
      automatic_tax: { enabled: false },
      tax_id_collection: { enabled: false },
      subscription_data: {
        metadata: {
          account_id: @account.id,
          plan: @plan,
          interval: @interval,
          ai: @ai,
          uptime_monitors: @uptime_monitors,
          extra_errors: @extra_errors,
          session_replays: @session_replays
        }
      },
      line_items: build_line_items
    )
  rescue Stripe::InvalidRequestError => e
    # Recover from stale / deleted Stripe customers, then retry once
    if e.message&.include?("No such customer")
      Rails.logger.warn "Stripe customer missing for user #{@user.id}, recreating: #{e.message}"
      recreate_stripe_customer!
      Stripe::Checkout::Session.create(
        mode: "subscription",
        customer: @user.payment_processor.processor_id,
        payment_method_collection: "if_required",
        success_url: success_url,
        cancel_url: cancel_url,
        allow_promotion_codes: true,
        client_reference_id: @account.id,
        automatic_tax: { enabled: false },
        tax_id_collection: { enabled: false },
        subscription_data: {
          metadata: {
            account_id: @account.id,
            plan: @plan,
            interval: @interval,
            ai: @ai
          }
        },
        line_items: build_line_items
      )
    else
      raise
    end
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

  def idempotency_key
    "checkout:#{@account.id}:#{@plan}:#{@interval}:#{@ai}"
  end

  def success_url
    host = ENV.fetch("APP_HOST")
    plan_q = CGI.escape(@plan.to_s)
    interval_q = CGI.escape(@interval.to_s)
    Rails.application.routes.url_helpers.dashboard_url(host: host) + "?subscribed=1&plan=#{plan_q}&interval=#{interval_q}"
  end

  def cancel_url
    Rails.application.routes.url_helpers.settings_url(host: ENV.fetch("APP_HOST")) + "?canceled=1"
  end
end
