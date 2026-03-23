# frozen_string_literal: true

class UptimeController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }
  before_action :set_monitor, only: [:show, :edit, :update, :destroy, :pause, :resume, :check_now]

  def index
    project_scope = @current_project || @project

    base_scope = if project_scope
                   project_scope.uptime_monitors
                 else
                   UptimeMonitor.where(account: current_account)
                 end

    @monitors = base_scope.order(created_at: :desc)

    # Summary stats
    @total_count = @monitors.count
    @up_count = @monitors.where(status: "up").count
    @down_count = @monitors.where(status: "down").count
    @degraded_count = @monitors.where(status: "degraded").count
    @paused_count = @monitors.where(status: "paused").count

    # 30-day uptime for each monitor
    @uptimes = UptimeDailySummary
      .where(uptime_monitor_id: @monitors.select(:id))
      .where(date: 30.days.ago.to_date..Date.current)
      .group(:uptime_monitor_id)
      .select(
        "uptime_monitor_id",
        "ROUND(AVG(uptime_percentage), 2) as avg_uptime",
        "ROUND(AVG(avg_response_time_ms)) as avg_response_time"
      )
      .index_by(&:uptime_monitor_id)
  end

  def show
    @pagy, @recent_checks = pagy(@monitor.uptime_checks.recent, limit: 25)
    @daily_summaries = @monitor.uptime_daily_summaries.recent.limit(30)

    # Data retention info
    @retention_days = current_account.data_retention_days

    # Calculate current uptime %
    @uptime_30d = @daily_summaries.any? ?
      (@daily_summaries.sum(&:uptime_percentage) / @daily_summaries.size).round(2) : nil
    @avg_response = @daily_summaries.any? ?
      @daily_summaries.filter_map(&:avg_response_time_ms).sum.to_f / @daily_summaries.filter_map(&:avg_response_time_ms).size : nil

    # Chart data (response times for last 24h)
    @chart_checks = @monitor.uptime_checks
      .where("created_at > ?", 24.hours.ago)
      .order(:created_at)
      .pluck(:created_at, :response_time_ms, :success)
  end

  def new
    @monitor = UptimeMonitor.new(
      http_method: "GET",
      expected_status_code: 200,
      interval_seconds: 300,
      timeout_seconds: 30,
      alert_threshold: 3
    )
    authorize @monitor
  end

  def create
    @monitor = UptimeMonitor.new(monitor_params)
    @monitor.project = @current_project || @project
    authorize @monitor

    # Count real UptimeMonitor records (not cached Healthcheck count)
    monitor_count = UptimeMonitor.where(account: current_account).count
    monitor_quota = current_account.uptime_monitors_quota
    unless monitor_count < monitor_quota
      flash.now[:alert] = "You've reached your uptime monitor limit (#{monitor_count}/#{monitor_quota}). Please upgrade your plan."
      render :new, status: :unprocessable_entity
      return
    end

    if @monitor.save
      redirect_to uptime_monitor_path(@monitor), notice: "Monitor created. First check will run shortly."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @monitor
  end

  def update
    authorize @monitor
    if @monitor.update(monitor_params)
      redirect_to uptime_monitor_path(@monitor), notice: "Monitor updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @monitor
    @monitor.destroy
    redirect_to uptime_index_path, notice: "Monitor deleted."
  end

  def pause
    authorize @monitor
    @monitor.pause!
    redirect_to uptime_monitor_path(@monitor), notice: "Monitor paused."
  end

  def resume
    authorize @monitor
    @monitor.resume!
    redirect_to uptime_monitor_path(@monitor), notice: "Monitor resumed. Next check will run shortly."
  end

  def check_now
    authorize @monitor

    # Rate limit: 1 manual check per 30 seconds
    lock_key = "check_now:#{@monitor.id}"
    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: 30, nx: true) }

    unless lock_acquired
      redirect_to uptime_monitor_path(@monitor), alert: "Please wait 30 seconds between manual checks."
      return
    end

    UptimePingJob.perform_async(@monitor.id)
    redirect_to uptime_monitor_path(@monitor), notice: "Check queued. Results will appear shortly."
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def set_monitor
    @monitor = UptimeMonitor.find(params[:id])
  end

  def monitor_params
    params.require(:uptime_monitor).permit(
      :name, :url, :http_method, :expected_status_code,
      :interval_seconds, :timeout_seconds, :alert_threshold, :body
    )
  end
end
