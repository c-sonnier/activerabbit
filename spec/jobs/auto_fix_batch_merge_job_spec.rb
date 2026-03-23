require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe AutoFixBatchMergeJob, type: :job do
  let(:account) { create(:account) }
  let(:project) do
    create(:project, account: account, settings: {
      "github_repo" => "owner/repo",
      "github_pat" => "ghp_test",
      "auto_fix" => { "enabled" => true, "auto_merge" => true, "skip_ci" => true },
      "issue_pr_urls" => {}
    })
  end

  let(:api_client) { instance_double(Github::ApiClient) }

  before do
    ActsAsTenant.current_tenant = account
    Sidekiq::Testing.fake!
    allow(Github::ApiClient).to receive(:new).and_return(api_client)
    allow(Github::TokenManager).to receive(:resolve_env_private_key).and_return(nil)
  end

  describe '#perform' do
    context 'with open ai-fix PRs' do
      let!(:issue) do
        create(:issue, project: project, account: account, status: "open").tap do |i|
          i.update_columns(auto_fix_status: "pr_created")
        end
      end

      before do
        settings = project.settings.merge("issue_pr_urls" => { issue.id.to_s => "https://github.com/owner/repo/pull/10" })
        project.update_column(:settings, settings)
      end

      it 'merges open PRs with ai-fix/ branch' do
        allow(api_client).to receive(:get_pr_info).and_return({
          number: 10, state: "open", merged: false, draft: false,
          head_branch: "ai-fix/test-fix", base_branch: "main",
          html_url: "https://github.com/owner/repo/pull/10", changed_files: 1
        })
        allow(api_client).to receive(:merge_pr).and_return({ success: true, sha: "abc123" })

        described_class.new.perform(project.id)
        issue.reload

        expect(issue.auto_fix_status).to eq("merged")
        expect(issue.auto_fix_merged_at).to be_present
      end

      it 'skips non-ai-fix branches' do
        allow(api_client).to receive(:get_pr_info).and_return({
          number: 10, state: "open", merged: false, draft: false,
          head_branch: "feature/manual-branch", base_branch: "main",
          html_url: "https://github.com/owner/repo/pull/10", changed_files: 2
        })

        expect(api_client).not_to receive(:merge_pr)
        described_class.new.perform(project.id)
      end

      it 'skips closed PRs' do
        allow(api_client).to receive(:get_pr_info).and_return({
          number: 10, state: "closed", merged: false, draft: false,
          head_branch: "ai-fix/test", base_branch: "main",
          html_url: "https://github.com/owner/repo/pull/10", changed_files: 1
        })

        expect(api_client).not_to receive(:merge_pr)
        described_class.new.perform(project.id)
      end

      it 'skips already merged PRs' do
        allow(api_client).to receive(:get_pr_info).and_return({
          number: 10, state: "closed", merged: true, draft: false,
          head_branch: "ai-fix/test", base_branch: "main",
          html_url: "https://github.com/owner/repo/pull/10", changed_files: 1
        })

        expect(api_client).not_to receive(:merge_pr)
        described_class.new.perform(project.id)
      end

      it 'undrafts draft PRs before merging' do
        allow(api_client).to receive(:get_pr_info).and_return({
          number: 10, state: "open", merged: false, draft: true,
          head_branch: "ai-fix/test", base_branch: "main",
          html_url: "https://github.com/owner/repo/pull/10", changed_files: 1
        })
        allow(api_client).to receive(:mark_pr_ready)
        allow(api_client).to receive(:merge_pr).and_return({ success: true, sha: "abc123" })

        described_class.new.perform(project.id)

        expect(api_client).to have_received(:mark_pr_ready).with("owner", "repo", 10)
      end
    end

    context 'when auto_merge is disabled' do
      it 'does nothing' do
        project.update!(settings: project.settings.deep_merge(
          "auto_fix" => { "auto_merge" => false }
        ))

        expect(api_client).not_to receive(:get_pr_info)
        described_class.new.perform(project.id)
      end
    end

    context 'when no PR URLs stored' do
      it 'returns early' do
        project.update_column(:settings, project.settings.merge("issue_pr_urls" => {}))

        expect(api_client).not_to receive(:get_pr_info)
        described_class.new.perform(project.id)
      end
    end
  end
end
