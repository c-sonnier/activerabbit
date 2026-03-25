class ReplaysController < ApplicationController
  layout "admin"
  before_action :authenticate_user!, except: [:data]
  before_action :set_project, except: [:data]

  def index
    @replays = @project.replays.ready.recent

    # Filtering
    @replays = @replays.where(environment: params[:environment]) if params[:environment].present?
    @replays = @replays.with_issue if params[:has_issue] == "true"

    # Search by URL
    @replays = @replays.where("url ILIKE ?", "%#{params[:q]}%") if params[:q].present?

    @replays = @replays.page(params[:page]).per(25)

    @stats = {
      total: @project.replays.ready.count,
      with_errors: @project.replays.ready.with_issue.count,
      avg_duration: @project.replays.ready.average(:duration_ms)&.to_i || 0
    }
  end

  def show
    @replay = @project.replays.find(params[:id])
    @replay_url = if @replay.storage_key&.start_with?("local://")
      project_replay_data_path(@project.slug, @replay)
    elsif @replay.storage_key.present? && ReplayStorage::BUCKET.present?
      ReplayStorage.client.presigned_url(key: @replay.storage_key) rescue nil
    end

    ready = @project.replays.ready.recent
    @prev_replay = ready.where("created_at > ?", @replay.created_at).last
    @next_replay = ready.where("created_at < ?", @replay.created_at).first
  end

  # Serve compressed replay data from local storage
  def data
    ActsAsTenant.without_tenant do
      replay = Replay.joins(:project)
                     .where(projects: { slug: params[:project_slug] })
                     .find(params[:id])

      unless replay.storage_key&.start_with?("local://")
        head :not_found
        return
      end

      key = replay.storage_key.delete_prefix("local://")
      local_path = Rails.root.join("storage", "replays", key)

      unless File.exist?(local_path)
        head :not_found
        return
      end

      # Disable mini-profiler for binary data responses
      Rack::MiniProfiler.deauthorize_request if defined?(Rack::MiniProfiler)

      send_file local_path, type: "application/octet-stream", disposition: "inline"
    end
  end

  private

  def set_project
    @project = current_account.projects.find_by!(slug: params[:project_slug])
  end
end
