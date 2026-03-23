require 'rails_helper'

RSpec.describe "Uptime", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :confirmed, account: account, role: "owner") }
  let(:project) { create(:project, account: account, user: user, tech_stack: "ruby") }

  before do
    ActsAsTenant.current_tenant = account
    sign_in user
  end

  describe "GET /uptime" do
    it "renders the index page" do
      get uptime_index_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /uptime/:id" do
    it "renders the show page" do
      monitor = create(:uptime_monitor, project: project)
      get uptime_monitor_path(monitor)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /uptime" do
    it "creates a monitor" do
      expect {
        post uptime_monitors_path, params: {
          uptime_monitor: {
            name: "Test", url: "https://example.com",
            interval_seconds: 300, http_method: "GET",
            expected_status_code: 200, timeout_seconds: 30,
            alert_threshold: 3
          }
        }
      }.to change { UptimeMonitor.count }.by(1)
      expect(response).to redirect_to(uptime_monitor_path(UptimeMonitor.last))
    end
  end

  describe "POST /uptime/:id/pause" do
    it "pauses the monitor" do
      monitor = create(:uptime_monitor, project: project, status: "up")
      post pause_uptime_monitor_path(monitor)
      expect(monitor.reload.status).to eq("paused")
    end
  end
end
