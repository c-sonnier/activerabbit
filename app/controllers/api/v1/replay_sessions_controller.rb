class Api::V1::ReplaySessionsController < Api::BaseController
  # POST /api/v1/replay_sessions
  def create
    unless Rails.env.development?
      ActsAsTenant.with_tenant(@current_project.account) do
        raw_events_json = params[:events].to_json

        # Upsert: if replay_id already exists for this project, update it with new events
        existing = @current_project.replays.find_by(replay_id: params[:replay_id])

        if existing
          # Re-ingest with updated events
          ReplayIngestJob.perform_async(existing.id, raw_events_json)
          render json: { status: "updated", replay_id: existing.replay_id }, status: :accepted
          return
        end

        # New replay
        if @current_project.account.replay_quota_exceeded?
          render json: { error: "quota_exceeded", message: "Replay quota exceeded" }, status: :too_many_requests
          return
        end

        replay = Replay.new(replay_params)
        replay.account = @current_project.account
        replay.project = @current_project
        replay.status = "pending"
        replay.retention_until = 30.days.from_now

        unless replay.save
          render json: {
            error: "validation_error",
            message: replay.errors.full_messages.join(", ")
          }, status: :unprocessable_entity
          return
        end

        @current_project.account.increment_replay_usage!

        ReplayIngestJob.perform_async(replay.id, raw_events_json)
        ReplayIssueLinkJob.perform_async(replay.id)

        render json: { status: "accepted", replay_id: replay.replay_id }, status: :accepted
      end
    end
  end

  private

  def replay_params
    params.permit(
      :replay_id,
      :session_id,
      :started_at,
      :duration_ms,
      :segment_index,
      :trigger_type,
      :trigger_error_class,
      :trigger_error_short,
      :trigger_offset_ms,
      :url,
      :user_agent,
      :viewport_width,
      :viewport_height,
      :environment,
      :release_version,
      :sdk_version,
      :rrweb_version
    )
  end
end
