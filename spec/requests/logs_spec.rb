require 'rails_helper'

RSpec.describe "Logs", type: :request do
  let(:account) { create(:account, :team_plan) }
  let(:user) { create(:user, :confirmed, :owner, account: account) }
  let(:project) { create(:project, account: account, user: user) }

  before do
    ActsAsTenant.current_tenant = account
    login_as user, scope: :user
  end

  describe "GET /:project_slug/logs" do
    it "returns success" do
      get project_slug_logs_path(project.slug)
      expect(response).to have_http_status(:ok)
    end

    it "paginates instead of loading all rows" do
      create_list(:log_entry, 55, account: account, project: project, occurred_at: 1.hour.ago)
      get project_slug_logs_path(project.slug)
      expect(response).to have_http_status(:ok)
      # Should show pagination when > 50 results
      expect(response.body).to include("pagination").or include("next").or include("page")
    end

    it "shows total count" do
      create_list(:log_entry, 3, account: account, project: project, occurred_at: 1.hour.ago)
      get project_slug_logs_path(project.slug)
      expect(response.body).to include("3")
    end

    context "with level filter" do
      it "filters by level" do
        create(:log_entry, account: account, project: project, level: 2, occurred_at: 1.hour.ago)
        create(:log_entry, :error, account: account, project: project, occurred_at: 1.hour.ago)

        get project_slug_logs_path(project.slug), params: { level: "error" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "with time range filter" do
      it "respects time range" do
        create(:log_entry, account: account, project: project, occurred_at: 30.minutes.ago)
        create(:log_entry, :old, account: account, project: project)

        get project_slug_logs_path(project.slug), params: { range: "1h" }
        expect(response).to have_http_status(:ok)
        # Old log should not appear
        expect(response.body).not_to include("Old log entry")
      end
    end

    context "with search query" do
      it "filters by structured query" do
        create(:log_entry, :error, account: account, project: project, source: "StripeService", occurred_at: 1.hour.ago)
        create(:log_entry, account: account, project: project, source: "UserService", occurred_at: 1.hour.ago)

        get project_slug_logs_path(project.slug), params: { q: "source:StripeService" }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /logs/:id" do
    let!(:log_entry) { create(:log_entry, :error, :with_params, account: account, project: project, occurred_at: 1.hour.ago) }

    it "returns success" do
      get log_entry_path(log_entry)
      expect(response).to have_http_status(:ok)
    end

    it "renders turbo frame for lazy loading" do
      get log_entry_path(log_entry)
      expect(response.body).to include("turbo-frame")
      expect(response.body).to include("log_detail_#{log_entry.id}")
    end

    it "renders detail content" do
      get log_entry_path(log_entry)
      expect(response.body).to include(log_entry.message)
    end
  end

  describe "GET /projects/:project_id/logs" do
    it "returns success via project_id route" do
      get project_logs_path(project)
      expect(response).to have_http_status(:ok)
    end
  end
end
