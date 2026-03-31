class CheckoutsController < ApplicationController
  before_action :authenticate_user!

  def create
    account = current_user.account
    plan = params.require(:plan)
    interval = params[:interval] # Optional for free plan
    ai = params[:ai]

    # Handle free plan separately (no Stripe checkout needed)
    if plan == "free"
      account.update!(
        current_plan: "free",
        billing_interval: "month" # Default, doesn't matter for free
      )
      redirect_to dashboard_path, notice: "You're now on the Free plan!"
      return
    end

    addon_params = {
      ai:,
      uptime_monitors: params[:uptime_monitors],
      extra_errors: params[:extra_errors],
      session_replays: params[:session_replays]
    }

    if account.active_subscription?
      # Update existing subscription (no new checkout needed)
      SubscriptionUpdater.new(
        account:, plan:, interval:, **addon_params
      ).call
      # Brief pause to let Stripe webhook arrive and update account
      sleep 5
      redirect_to plan_path, notice: "Your plan has been updated!"
    else
      # New subscription — go through Stripe checkout
      url = CheckoutCreator.new(
        user: current_user, account:, plan:, interval:, **addon_params
      ).call.url
      redirect_to url, allow_other_host: true, status: :see_other
    end
  rescue => e
    Rails.logger.error "[CheckoutsController] #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    redirect_to plan_path, alert: e.message
  end
end
