# frozen_string_literal: true

class CheckInsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_check_in, only: [:show, :edit, :update, :destroy, :pause, :resume]

  def index
    base_scope = ::CheckIn.where(account: current_account)
    base_scope = base_scope.where(project_id: current_project.id) if current_project.present?

    @check_ins = base_scope.order(created_at: :desc)
    @total_count = @check_ins.count
    @healthy_count = @check_ins.select { |c| c.status_display == "healthy" }.size
    @missed_count = @check_ins.select { |c| c.status_display == "missed" }.size
    @new_count = @check_ins.select { |c| c.status_display == "new" }.size
  end

  def show
    @project = @check_in.project
    @recent_pings = @check_in.pings.recent.limit(50)
    @pings_24h = @check_in.pings.last_24h.count
    @pings_7d = @check_in.pings.last_7d.count
    @pings_30d = @check_in.pings.last_30d.count
    @uptime_percentage = calculate_uptime(@check_in)
    @ping_timeline = build_ping_timeline(@check_in)
  end

  def new
    @check_in = ::CheckIn.new(
      kind: "heartbeat",
      heartbeat_interval_seconds: 86400,
      timezone: "UTC",
      enabled: true
    )
    if current_project.present?
      @check_in.project = current_project
      @check_in_project_locked = true
    elsif (p = selected_project_for_menu)
      @check_in.project_id = p.id
    end
  end

  def create
    @check_in = ::CheckIn.new(check_in_params)
    assign_check_in_project(@check_in)

    if @check_in.save
      redirect_to check_in_path(@check_in), notice: "Check-in created. Follow the setup steps on this page — same API key as error tracking, one monitor slug line in your app."
    else
      @check_in_project_locked = current_project.present?
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @check_in.update(check_in_params)
      redirect_to check_in_path(@check_in), notice: "Check-in updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @check_in.destroy
    redirect_to check_ins_path, notice: "Check-in deleted."
  end

  def pause
    @check_in.update!(enabled: false)
    redirect_to check_in_path(@check_in), notice: "Check-in paused."
  end

  def resume
    @check_in.update!(enabled: true)
    redirect_to check_in_path(@check_in), notice: "Check-in resumed."
  end

  private

  def assign_check_in_project(record)
    pid = params.dig(:check_in, :project_id).presence
    if pid.present?
      record.project = current_account.projects.find(pid)
    elsif current_project.present?
      record.project = current_project
    end
  end

  def set_check_in
    @check_in = ::CheckIn.find(params[:id])
  end

  def check_in_params
    params.require(:check_in).permit(
      :description, :kind, :heartbeat_interval_seconds,
      :enabled, :project_id
    )
  end

  def calculate_uptime(check_in)
    return nil if check_in.last_seen_at.nil?

    interval = check_in.heartbeat_interval_seconds
    return nil unless interval&.positive?

    hours_since_creation = [(Time.current - check_in.created_at) / 1.hour, 1].max
    expected_pings = (hours_since_creation * 3600 / interval).floor
    return 100.0 if expected_pings.zero?

    actual_pings = check_in.pings.count
    [(actual_pings.to_f / expected_pings * 100).round(1), 100.0].min
  end

  def build_ping_timeline(check_in)
    pings = check_in.pings.where(pinged_at: 24.hours.ago..).order(:pinged_at)
    interval = check_in.heartbeat_interval_seconds || 3600

    slots = []
    slot_duration = if interval <= 300
                     300
    elsif interval <= 3600
                     3600
    else
                     interval
    end

    cursor = 24.hours.ago.beginning_of_hour
    while cursor < Time.current
      slot_end = cursor + slot_duration
      count = pings.count { |p| p.pinged_at >= cursor && p.pinged_at < slot_end }
      expected = slot_duration >= interval ? 1 : 0

      status = if check_in.last_seen_at.nil? && count.zero?
                 "empty"
      elsif count > 0
                 "ok"
      elsif expected > 0 && cursor < Time.current - interval
                 "missed"
      else
                 "pending"
      end

      slots << { time: cursor, count: count, status: status }
      cursor = slot_end
    end

    slots
  end
end
