require 'rails_helper'

RSpec.describe Github::ApiClient, type: :service do
  let(:token) { "ghp_test_token" }
  let(:client) { described_class.new(token) }
  let(:owner) { "owner" }
  let(:repo) { "repo" }

  describe '#get_pr_info' do
    it 'returns parsed PR info on success' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42")
        .to_return(status: 200, body: {
          "number" => 42,
          "state" => "open",
          "merged" => false,
          "title" => "Fix bug",
          "html_url" => "https://github.com/#{owner}/#{repo}/pull/42",
          "head" => { "ref" => "ai-fix/some-branch" },
          "base" => { "ref" => "main" },
          "updated_at" => "2026-03-18T12:00:00Z",
          "draft" => true,
          "changed_files" => 3
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      info = client.get_pr_info(owner, repo, 42)

      expect(info[:number]).to eq(42)
      expect(info[:state]).to eq("open")
      expect(info[:merged]).to be false
      expect(info[:head_branch]).to eq("ai-fix/some-branch")
      expect(info[:draft]).to be true
      expect(info[:changed_files]).to eq(3)
    end

    it 'returns nil when PR not found' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/pulls/999")
        .to_return(status: 404, body: { "message" => "Not Found" }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.get_pr_info(owner, repo, 999)).to be_nil
    end

    it 'returns changed_files as 0 for empty PRs' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/pulls/10")
        .to_return(status: 200, body: {
          "number" => 10, "state" => "open", "merged" => false,
          "title" => "Empty PR", "html_url" => "https://github.com/#{owner}/#{repo}/pull/10",
          "head" => { "ref" => "ai-fix/empty" }, "base" => { "ref" => "main" },
          "updated_at" => "2026-03-18T12:00:00Z", "draft" => false, "changed_files" => 0
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      info = client.get_pr_info(owner, repo, 10)
      expect(info[:changed_files]).to eq(0)
    end
  end

  describe '#combined_status' do
    it 'returns parsed status' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/commits/abc123/status")
        .to_return(status: 200, body: {
          "state" => "success", "total_count" => 2
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.combined_status(owner, repo, "abc123")
      expect(result[:state]).to eq("success")
      expect(result[:total_count]).to eq(2)
    end

    it 'returns empty hash on error' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/commits/bad/status")
        .to_raise(StandardError.new("connection failed"))

      expect(client.combined_status(owner, repo, "bad")).to eq({})
    end
  end

  describe '#check_runs_status' do
    it 'returns parsed check runs' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/commits/abc123/check-runs")
        .to_return(status: 200, body: {
          "total_count" => 2,
          "check_runs" => [
            { "status" => "completed", "conclusion" => "success" },
            { "status" => "completed", "conclusion" => "success" }
          ]
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.check_runs_status(owner, repo, "abc123")
      expect(result[:total_count]).to eq(2)
      expect(result[:conclusions]).to eq(%w[success success])
      expect(result[:in_progress_count]).to eq(0)
    end

    it 'counts in-progress runs' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/commits/abc123/check-runs")
        .to_return(status: 200, body: {
          "total_count" => 2,
          "check_runs" => [
            { "status" => "completed", "conclusion" => "success" },
            { "status" => "in_progress", "conclusion" => nil }
          ]
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.check_runs_status(owner, repo, "abc123")
      expect(result[:in_progress_count]).to eq(1)
    end
  end

  describe '#merge_pr' do
    it 'returns success when merged' do
      stub_request(:put, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42/merge")
        .to_return(status: 200, body: {
          "merged" => true, "sha" => "merge_sha_123"
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.merge_pr(owner, repo, 42)
      expect(result[:success]).to be true
      expect(result[:sha]).to eq("merge_sha_123")
    end

    it 'returns failure when merge blocked' do
      stub_request(:put, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42/merge")
        .to_return(status: 405, body: {
          "message" => "Pull Request is not mergeable"
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.merge_pr(owner, repo, 42)
      expect(result[:success]).to be false
      expect(result[:error]).to include("405")
    end
  end

  describe '#close_pr' do
    it 'sends PATCH with state closed' do
      stub_request(:patch, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42")
        .with(body: { state: "closed" }.to_json)
        .to_return(status: 200, body: { "state" => "closed" }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.close_pr(owner, repo, 42)
      expect(result).to be_a(Hash)
    end
  end

  describe '#mark_pr_ready' do
    it 'sends PATCH with draft false' do
      stub_request(:patch, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42")
        .with(body: { draft: false }.to_json)
        .to_return(status: 200, body: { "draft" => false }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.mark_pr_ready(owner, repo, 42)
      expect(result).to be_a(Hash)
    end
  end

  describe '#reopen_pr' do
    it 'sends PATCH with state open' do
      stub_request(:patch, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42")
        .with(body: { state: "open" }.to_json)
        .to_return(status: 200, body: { "state" => "open" }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.reopen_pr(owner, repo, 42)
      expect(result).to be_a(Hash)
    end

    it 'returns error when branch deleted' do
      stub_request(:patch, "https://api.github.com/repos/#{owner}/#{repo}/pulls/42")
        .to_return(status: 422, body: {
          "message" => "Validation Failed"
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.reopen_pr(owner, repo, 42)
      expect(result[:error]).to be_present
    end
  end

  describe '#detect_default_branch' do
    it 'returns the default branch name' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}")
        .to_return(status: 200, body: { "default_branch" => "main" }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.detect_default_branch(owner, repo)).to eq("main")
    end

    it 'returns nil on error' do
      stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}")
        .to_return(status: 404, body: { "message" => "Not Found" }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(client.detect_default_branch(owner, repo)).to be_nil
    end
  end
end
