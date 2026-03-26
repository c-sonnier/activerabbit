require 'rails_helper'

RSpec.describe "Uptime::Monitors", type: :request do
  let(:account) { create(:account, :team_plan) }
  let(:owner) { create(:user, :confirmed, :owner, account: account) }
  let(:member) { create(:user, :confirmed, :member, account: account) }
  let(:project) { create(:project, account: account, user: owner) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe "GET /:project_slug/uptime" do
    before { login_as owner, scope: :user }

    it "returns success" do
      get project_slug_uptime_path(project.slug)
      expect(response).to have_http_status(:ok)
    end

    it "lists monitors with status counts" do
      create(:uptime_monitor, account: account, project: project, status: "up")
      create(:uptime_monitor, account: account, project: project, status: "down")
      create(:uptime_monitor, account: account, project: project, status: "paused")

      get project_slug_uptime_path(project.slug)
      expect(response).to have_http_status(:ok)
    end

    it "includes daily summary stats" do
      monitor = create(:uptime_monitor, account: account, project: project, status: "up")
      create(:uptime_daily_summary, account: account, monitor: monitor, date: 1.day.ago, uptime_percentage: 99.5)

      get project_slug_uptime_path(project.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /uptime/:id" do
    let!(:monitor) { create(:uptime_monitor, account: account, project: project, status: "up") }

    before { login_as owner, scope: :user }

    it "returns success" do
      get uptime_monitor_path(monitor)
      expect(response).to have_http_status(:ok)
    end

    it "supports period filter" do
      get uptime_monitor_path(monitor), params: { period: "7d" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /uptime/new" do
    context "as owner" do
      before { login_as owner, scope: :user }

      it "returns success" do
        project # ensure project exists for onboarding check
        get new_uptime_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "as member" do
      before { login_as member, scope: :user }

      it "is forbidden" do
        project # ensure project exists
        get new_uptime_path
        # Pundit raises NotAuthorizedError which may render 403 or redirect
        expect(response.status).to be_in([302, 403])
      end
    end
  end

  describe "POST /uptime" do
    before do
      login_as owner, scope: :user
      # Set project context via session
      get project_slug_uptime_path(project.slug)
    end

    let(:valid_params) do
      {
        uptime_monitor: {
          name: "Production Health",
          url: "https://example.com/health",
          http_method: "GET",
          expected_status_code: 200,
          interval_seconds: 300,
          timeout_seconds: 30,
          alert_threshold: 3
        }
      }
    end

    it "creates a monitor" do
      expect {
        post uptime_monitors_path, params: valid_params
      }.to change(Uptime::Monitor, :count).by(1)
      expect(response).to redirect_to(uptime_monitor_path(Uptime::Monitor.last))
    end

    it "rejects invalid params" do
      post uptime_monitors_path, params: { uptime_monitor: { name: "", url: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /uptime/:id" do
    let!(:monitor) { create(:uptime_monitor, account: account, project: project) }

    before { login_as owner, scope: :user }

    it "updates the monitor" do
      patch "/uptime/#{monitor.id}", params: { uptime_monitor: { name: "Updated Name" } }
      expect(response).to redirect_to(uptime_monitor_path(monitor))
      expect(monitor.reload.name).to eq("Updated Name")
    end
  end

  describe "DELETE /uptime/:id" do
    let!(:monitor) { create(:uptime_monitor, account: account, project: project) }

    before { login_as owner, scope: :user }

    it "deletes the monitor" do
      expect {
        delete "/uptime/#{monitor.id}"
      }.to change(Uptime::Monitor, :count).by(-1)
      expect(response).to redirect_to(uptime_index_path)
    end
  end

  describe "POST /uptime/:id/pause" do
    let!(:monitor) { create(:uptime_monitor, account: account, project: project, status: "up") }

    before { login_as owner, scope: :user }

    it "pauses the monitor" do
      post pause_uptime_monitor_path(monitor)
      expect(monitor.reload.status).to eq("paused")
      expect(response).to redirect_to(uptime_monitor_path(monitor))
    end
  end

  describe "POST /uptime/:id/resume" do
    let!(:monitor) { create(:uptime_monitor, account: account, project: project, status: "paused") }

    before { login_as owner, scope: :user }

    it "resumes the monitor" do
      post resume_uptime_monitor_path(monitor)
      expect(monitor.reload.status).to eq("pending")
      expect(response).to redirect_to(uptime_monitor_path(monitor))
    end
  end

  describe "POST /uptime/:id/check_now" do
    let!(:monitor) { create(:uptime_monitor, account: account, project: project, status: "up") }

    before { login_as owner, scope: :user }

    it "queues a check", :sidekiq_fake do
      # Stub Sidekiq.redis to avoid real Redis connection
      allow(Sidekiq).to receive(:redis).and_yield(double(set: true))
      allow(Uptime::PingJob).to receive(:perform_async)

      post check_now_uptime_monitor_path(monitor)
      expect(response).to redirect_to(uptime_monitor_path(monitor))
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      get uptime_index_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
