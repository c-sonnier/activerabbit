class LogsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] || params[:project_slug] }

  def index
    scope = if @project
      LogEntry.where(project: @project)
    else
      LogEntry.where(project_id: current_account.project_ids)
    end

    # Apply search/filters
    if params[:q].present?
      filters = LogSearchQueryParser.parse(params[:q])
      scope = apply_filters(scope, filters)
    end

    if params[:level].present?
      scope = scope.by_level(params[:level].to_sym)
    end

    if params[:environment].present?
      scope = scope.where(environment: params[:environment])
    end

    # Time range
    time_range = parse_time_range(params[:range] || "24h")
    scope = scope.where("occurred_at > ?", time_range.ago) if time_range

    @logs = scope.reverse_chronological.limit(200)
    @total_count = scope.count

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @log_entry = LogEntry.find(params[:id])

    respond_to do |format|
      format.html
      format.turbo_stream { render partial: "logs/log_entry_detail", locals: { log_entry: @log_entry } }
    end
  end

  private

  def set_project
    @project = if params[:project_slug]
      current_account.projects.find_by!(slug: params[:project_slug])
    else
      current_account.projects.find(params[:project_id])
    end
  end

  def apply_filters(scope, filters)
    scope = scope.by_level(filters[:level]) if filters[:level]
    scope = scope.where(environment: filters[:environment]) if filters[:environment]
    scope = scope.where(source: filters[:source]) if filters[:source]
    scope = scope.where("message ILIKE ?", "%#{LogStore.send(:sanitize_like, filters[:message])}%") if filters[:message]
    scope = scope.where(trace_id: filters[:trace_id]) if filters[:trace_id]
    scope = scope.where(request_id: filters[:request_id]) if filters[:request_id]

    if filters[:params]
      filters[:params].each do |key, value|
        scope = scope.where("params @> ?", { key => value }.to_json)
      end
    end

    scope
  end

  def parse_time_range(range)
    case range
    when "1h" then 1.hour
    when "6h" then 6.hours
    when "24h" then 24.hours
    when "7d" then 7.days
    when "30d" then 30.days
    else 24.hours
    end
  end
end
