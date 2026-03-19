require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe AutoFixMonitorJob, type: :job do
  let(:account) { create(:account) }
  let(:project) do
    create(:project, account: account, settings: {
      "github_repo" => "owner/repo",
      "github_pat" => "ghp_test",
      "auto_fix" => { "enabled" => true, "auto_merge" => true, "skip_ci" => false }
    })
  end
  let(:issue) do
    create(:issue, project: project, account: account, status: "open").tap do |i|
      i.update_columns(
        auto_fix_status: "pr_created",
        auto_fix_pr_url: "https://github.com/owner/repo/pull/42",
        auto_fix_pr_number: 42,
        auto_fix_branch: "ai-fix/test-fix",
        auto_fix_attempted_at: Time.current
      )
    end
  end

  let(:api_client) { instance_double(Github::ApiClient) }

  before do
    ActsAsTenant.current_tenant = account
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all

    allow(Github::ApiClient).to receive(:new).and_return(api_client)
    allow(Github::TokenManager).to receive(:resolve_env_private_key).and_return(nil)
  end

  describe '#perform' do
    context 'when CI passes' do
      it 'merges the PR and updates issue status' do
        allow(api_client).to receive(:combined_status).and_return({ state: "success", total_count: 1 })
        allow(api_client).to receive(:check_runs_status).and_return({ total_count: 0, conclusions: [], in_progress_count: 0 })
        allow(api_client).to receive(:mark_pr_ready)
        allow(api_client).to receive(:merge_pr).and_return({ success: true, sha: "merge123" })

        described_class.new.perform(issue.id, project.id, 0)
        issue.reload

        expect(issue.auto_fix_status).to eq("merged")
        expect(issue.auto_fix_merged_at).to be_present
        expect(issue.status).to eq("closed")
      end
    end

    context 'when CI fails' do
      it 'sets ci_failed status' do
        allow(api_client).to receive(:combined_status).and_return({ state: "failure", total_count: 1 })
        allow(api_client).to receive(:check_runs_status).and_return({ total_count: 0, conclusions: [], in_progress_count: 0 })

        described_class.new.perform(issue.id, project.id, 0)
        issue.reload

        expect(issue.auto_fix_status).to eq("ci_failed")
        expect(issue.auto_fix_error).to include("CI checks failed")
      end
    end

    context 'when CI is pending' do
      it 're-enqueues itself' do
        allow(api_client).to receive(:combined_status).and_return({ state: "pending", total_count: 1 })
        allow(api_client).to receive(:check_runs_status).and_return({ total_count: 1, conclusions: [], in_progress_count: 1 })

        described_class.new.perform(issue.id, project.id, 0)
        issue.reload

        expect(issue.auto_fix_status).to eq("ci_pending")
        expect(AutoFixMonitorJob.jobs.size).to eq(1)
      end
    end

    context 'when skip_ci is enabled' do
      before do
        project.update!(settings: project.settings.deep_merge(
          "auto_fix" => { "skip_ci" => true }
        ))
      end

      it 'merges immediately without checking CI' do
        allow(api_client).to receive(:mark_pr_ready)
        allow(api_client).to receive(:merge_pr).and_return({ success: true, sha: "merge123" })

        expect(api_client).not_to receive(:combined_status)
        expect(api_client).not_to receive(:check_runs_status)

        described_class.new.perform(issue.id, project.id, 0)
        issue.reload

        expect(issue.auto_fix_status).to eq("merged")
      end
    end

    context 'when merge fails' do
      it 'sets merge_failed status' do
        allow(api_client).to receive(:combined_status).and_return({ state: "success", total_count: 1 })
        allow(api_client).to receive(:check_runs_status).and_return({ total_count: 0, conclusions: [], in_progress_count: 0 })
        allow(api_client).to receive(:mark_pr_ready)
        allow(api_client).to receive(:merge_pr).and_return({ success: false, error: "Merge conflict" })

        described_class.new.perform(issue.id, project.id, 0)
        issue.reload

        expect(issue.auto_fix_status).to eq("merge_failed")
        expect(issue.auto_fix_error).to eq("Merge conflict")
      end
    end

    context 'when max attempts exceeded' do
      it 'sets ci_timeout status' do
        described_class.new.perform(issue.id, project.id, AutoFixMonitorJob::MAX_POLL_ATTEMPTS)
        issue.reload

        expect(issue.auto_fix_status).to eq("ci_timeout")
      end
    end

    context 'when issue is not monitorable' do
      it 'skips issues with wrong status' do
        issue.update_columns(auto_fix_status: "merged")

        expect(api_client).not_to receive(:combined_status)
        described_class.new.perform(issue.id, project.id, 0)
      end

      it 'skips issues without ai-fix/ branch prefix' do
        issue.update_columns(auto_fix_branch: "manual-branch")

        expect(api_client).not_to receive(:combined_status)
        described_class.new.perform(issue.id, project.id, 0)
      end
    end
  end

  describe '#resolve_ci_status (private)' do
    let(:job) { described_class.new }

    it 'returns :success when no CI configured' do
      result = job.send(:resolve_ci_status,
        { state: nil, total_count: 0 },
        { total_count: 0, conclusions: [], in_progress_count: 0 })
      expect(result).to eq(:success)
    end

    it 'returns :failure on status failure' do
      result = job.send(:resolve_ci_status,
        { state: "failure", total_count: 1 },
        { total_count: 0, conclusions: [], in_progress_count: 0 })
      expect(result).to eq(:failure)
    end

    it 'returns :failure on check run failure' do
      result = job.send(:resolve_ci_status,
        { state: nil, total_count: 0 },
        { total_count: 1, conclusions: ["failure"], in_progress_count: 0 })
      expect(result).to eq(:failure)
    end

    it 'returns :pending when checks in progress' do
      result = job.send(:resolve_ci_status,
        { state: nil, total_count: 0 },
        { total_count: 2, conclusions: ["success"], in_progress_count: 1 })
      expect(result).to eq(:pending)
    end

    it 'returns :success when all checks pass' do
      result = job.send(:resolve_ci_status,
        { state: "success", total_count: 1 },
        { total_count: 2, conclusions: %w[success neutral], in_progress_count: 0 })
      expect(result).to eq(:success)
    end
  end
end
