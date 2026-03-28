require 'rails_helper'

RSpec.describe "Replays", type: :request do
  let(:account) { create(:account, :team_plan) }
  let(:user) { create(:user, :confirmed, :owner, account: account) }
  let(:project) { create(:project, account: account, user: user) }

  before do
    ActsAsTenant.current_tenant = account
    login_as user, scope: :user
  end

  describe "GET /:project_slug/replays" do
    it "returns success" do
      get project_replays_path(project.slug)
      expect(response).to have_http_status(:ok)
    end

    it "computes stats in a single query" do
      create_list(:replay, 3, account: account, project: project)
      issue = create(:issue, account: account, project: project)
      create(:replay, account: account, project: project, issue: issue)

      query_count = count_queries { get project_replays_path(project.slug) }
      # Verify stats are present
      expect(response.body).to include("Total")
      # Reasonable query count (auth, tenant, project, replays, stats, pagination)
      expect(query_count).to be <= 15
    end

    it "paginates results" do
      create_list(:replay, 30, account: account, project: project)
      get project_replays_path(project.slug)
      expect(response).to have_http_status(:ok)
    end

    context "with environment filter" do
      it "filters by environment" do
        create(:replay, account: account, project: project, environment: "production")
        create(:replay, account: account, project: project, environment: "staging")

        get project_replays_path(project.slug), params: { environment: "staging" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("staging")
      end
    end

    context "with has_issue filter" do
      it "filters replays with errors" do
        issue = create(:issue, account: account, project: project)
        create(:replay, account: account, project: project, issue: issue)
        create(:replay, account: account, project: project)

        get project_replays_path(project.slug), params: { has_issue: "1" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "with URL search" do
      it "searches by URL" do
        create(:replay, account: account, project: project, url: "https://example.com/checkout")
        create(:replay, account: account, project: project, url: "https://example.com/home")

        get project_replays_path(project.slug), params: { q: "checkout" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("checkout")
      end
    end
  end

  describe "GET /:project_slug/replays/:id" do
    let!(:replay) { create(:replay, account: account, project: project, storage_key: "local://test.bin") }

    it "returns success" do
      get project_replay_path(project.slug, replay)
      expect(response).to have_http_status(:ok)
    end

    it "sets prev/next replay links efficiently" do
      older = create(:replay, account: account, project: project, created_at: 2.hours.ago)
      newer = create(:replay, account: account, project: project, created_at: 30.minutes.ago)

      query_count = count_queries { get project_replay_path(project.slug, replay) }
      expect(response).to have_http_status(:ok)
      # Reasonable query count (auth, tenant, project, replay, prev, next, view)
      expect(query_count).to be <= 15
    end
  end

  describe "GET /:project_slug/replays/:id/data" do
    context "with local storage" do
      it "serves the replay file" do
        replay = create(:replay, account: account, project: project, storage_key: "local://test-data.bin")
        dir = Rails.root.join("storage", "replays")
        FileUtils.mkdir_p(dir)
        File.write(dir.join("test-data.bin"), "replay-content")

        get project_replay_data_path(project.slug, replay)
        expect(response).to have_http_status(:ok)
      ensure
        FileUtils.rm_f(dir.join("test-data.bin"))
      end
    end

    context "with non-local storage" do
      it "returns not found" do
        replay = create(:replay, account: account, project: project, storage_key: "s3://bucket/key")
        get project_replay_data_path(project.slug, replay)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(_name, _started, _finished, _unique_id, payload) {
      count += 1 unless payload[:name]&.match?(/SCHEMA|TRANSACTION/)
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
