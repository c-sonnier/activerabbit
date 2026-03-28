class ReplaysController < ApplicationController
  layout "admin"
  before_action :authenticate_user!, except: [:data]
  before_action :set_project, except: [:data]

  def index
    @replays = @project.replays.ready.recent

    # Filtering
    @replays = @replays.where(environment: params[:environment]) if params[:environment].present?
    @replays = @replays.with_issue if params[:has_issue].in?(%w[true 1])

    # Search by URL
    @replays = @replays.where("url ILIKE ?", "%#{params[:q]}%") if params[:q].present?

    @replays = @replays.page(params[:page]).per(25)

    stats_row = @project.replays.ready
      .select("COUNT(*) AS total, COUNT(issue_id) AS with_errors, COALESCE(AVG(CASE WHEN duration_ms > 0 AND duration_ms < 3600000 THEN duration_ms END), 0)::integer AS avg_duration")
      .take
    @stats = { total: stats_row.total, with_errors: stats_row.with_errors, avg_duration: stats_row.avg_duration }
  end

  def show
    @replay = @project.replays.find(params[:id])
    @replay_url = project_replay_data_path(@project.slug, @replay) if @replay.storage_key.present?

    @prev_replay = @project.replays.ready.where("created_at > ?", @replay.created_at).order(created_at: :asc).limit(1).first
    @next_replay = @project.replays.ready.where("created_at < ?", @replay.created_at).order(created_at: :desc).limit(1).first
  end

  # Serve replay data — proxies from local storage or R2
  def data
    ActsAsTenant.without_tenant do
      replay = Replay.joins(:project)
                     .where(projects: { slug: params[:project_slug] })
                     .find(params[:id])

      unless replay.storage_key.present?
        head :not_found
        return
      end

      # Disable mini-profiler for binary data responses
      Rack::MiniProfiler.deauthorize_request if defined?(Rack::MiniProfiler)

      if replay.storage_key.start_with?("local://")
        key = replay.storage_key.delete_prefix("local://")
        local_path = Rails.root.join("storage", "replays", key)

        unless File.exist?(local_path)
          head :not_found
          return
        end

        send_file local_path, type: "application/octet-stream", disposition: "inline"
      elsif ReplayStorage::BUCKET.present?
        # Proxy from R2 to avoid CORS issues
        data = ReplayStorage.client.download(key: replay.storage_key)
        send_data data, type: "application/octet-stream", disposition: "inline"
      else
        head :not_found
      end
    end
  end

  private

  def set_project
    @project = current_account.projects.find_by!(slug: params[:project_slug])
  end
end
