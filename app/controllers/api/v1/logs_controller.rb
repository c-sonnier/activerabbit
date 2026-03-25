class Api::V1::LogsController < Api::BaseController
  # POST /api/v1/logs
  def create
    unless @current_project
      render json: { error: "project_not_found", message: "Project not found" }, status: :not_found
      return
    end

    # Check log quota
    account = @current_project.account
    if account && !account.within_quota?(:log_entries)
      render json: {
        error: "quota_exceeded",
        message: "Log quota exceeded. Upgrade your plan for higher limits."
      }, status: :too_many_requests
      return
    end

    entries = params[:logs] || params[:entries] || [params.except(:controller, :action, :format)]
    entries = [entries] unless entries.is_a?(Array)

    if entries.empty?
      render json: { error: "validation_failed", message: "No log entries provided" }, status: :unprocessable_entity
      return
    end

    if entries.size > 1000
      render json: { error: "validation_failed", message: "Batch size exceeds maximum of 1000 entries" }, status: :unprocessable_entity
      return
    end

    # Validate each entry has required fields
    entries.each_with_index do |entry, i|
      if entry[:message].blank? && entry["message"].blank?
        render json: {
          error: "validation_failed",
          message: "Entry #{i} missing required field: message"
        }, status: :unprocessable_entity
        return
      end
    end

    serializable = entries.map { |e| JSON.parse(e.to_h.to_json) }
    LogIngestJob.perform_async(@current_project.id, serializable)

    render json: {
      status: "accepted",
      message: "#{entries.size} log entries queued for processing",
      project_id: @current_project.id
    }, status: :accepted
  rescue => e
    Rails.logger.error "[LogsAPI] Error: #{e.message}"
    render json: { error: "processing_error", message: e.message }, status: :internal_server_error
  end
end
