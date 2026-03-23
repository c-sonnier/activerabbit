require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe AutoFixCleanupJob, type: :job do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }

  before do
    ActsAsTenant.current_tenant = account
    Sidekiq::Testing.fake!
  end

  describe '#perform' do
    it 'marks stale creating_pr issues as timed out' do
      issue = create(:issue, project: project, account: account, status: "open")
      issue.update_columns(
        auto_fix_status: "creating_pr",
        auto_fix_attempted_at: 3.hours.ago
      )

      described_class.new.perform
      issue.reload

      expect(issue.auto_fix_status).to eq("ci_timeout")
      expect(issue.auto_fix_error).to include("Timed out")
    end

    it 'marks stale ci_pending issues as timed out' do
      issue = create(:issue, project: project, account: account, status: "open")
      issue.update_columns(
        auto_fix_status: "ci_pending",
        auto_fix_attempted_at: 3.hours.ago
      )

      described_class.new.perform
      issue.reload

      expect(issue.auto_fix_status).to eq("ci_timeout")
    end

    it 'does not touch recent issues' do
      issue = create(:issue, project: project, account: account, status: "open")
      issue.update_columns(
        auto_fix_status: "creating_pr",
        auto_fix_attempted_at: 30.minutes.ago
      )

      described_class.new.perform
      issue.reload

      expect(issue.auto_fix_status).to eq("creating_pr")
    end

    it 'does not touch issues with other statuses' do
      issue = create(:issue, project: project, account: account, status: "open")
      issue.update_columns(
        auto_fix_status: "pr_created",
        auto_fix_attempted_at: 3.hours.ago
      )

      described_class.new.perform
      issue.reload

      expect(issue.auto_fix_status).to eq("pr_created")
    end

    it 'handles no stale issues gracefully' do
      expect { described_class.new.perform }.not_to raise_error
    end
  end
end
