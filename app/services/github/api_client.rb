# frozen_string_literal: true

module Github
  # GitHub API client for making HTTP requests to GitHub API
  class ApiClient
    def initialize(token)
      @token = token
    end

    def get(path)
      http_json("https://api.github.com#{path}", headers)
    end

    def post(path, body)
      result = http_post_json("https://api.github.com#{path}", body, headers)
      return { error: result[:error] } if result.is_a?(Hash) && result[:error]
      result
    end

    def patch(path, body)
      result = http_patch_json("https://api.github.com#{path}", body, headers)
      return { error: result[:error] } if result.is_a?(Hash) && result[:error]
      result
    end

    def detect_default_branch(owner, repo)
      repo_json = get("/repos/#{owner}/#{repo}")
      Rails.logger.info "[GitHub API] Repo response keys: #{repo_json.keys rescue 'error'}"
      if repo_json.is_a?(Hash) && repo_json["message"]
        Rails.logger.error "[GitHub API] Error getting repo: #{repo_json['message']}"
        return nil
      end
      default_branch = repo_json.is_a?(Hash) ? repo_json["default_branch"] : nil
      Rails.logger.info "[GitHub API] default_branch=#{default_branch.inspect} for #{owner}/#{repo}"
      default_branch
    rescue => e
      Rails.logger.error "[GitHub API] detect_default_branch error: #{e.message}"
      nil
    end

    def get_pr_info(owner, repo, pr_number)
      pr = get("/repos/#{owner}/#{repo}/pulls/#{pr_number}")
      return nil unless pr.is_a?(Hash) && pr["number"]

      {
        number: pr["number"],
        state: pr["state"],
        merged: pr["merged"] || false,
        title: pr["title"],
        html_url: pr["html_url"],
        head_branch: pr.dig("head", "ref"),
        base_branch: pr.dig("base", "ref"),
        updated_at: pr["updated_at"],
        draft: pr["draft"] || false
      }
    rescue => e
      Rails.logger.error "[GitHub API] get_pr_info error: #{e.message}"
      nil
    end

    def reopen_pr(owner, repo, pr_number)
      patch("/repos/#{owner}/#{repo}/pulls/#{pr_number}", { state: "open" })
    end

    # Combined commit status (legacy status API)
    # Returns { state: "success"|"failure"|"pending", total_count: N }
    def combined_status(owner, repo, ref)
      data = get("/repos/#{owner}/#{repo}/commits/#{ref}/status")
      return {} unless data.is_a?(Hash)
      { state: data["state"], total_count: data["total_count"].to_i }
    rescue => e
      Rails.logger.error "[GitHub API] combined_status error: #{e.message}"
      {}
    end

    # Check runs status (GitHub Actions / Checks API)
    # Returns { total_count: N, conclusions: [...], in_progress_count: N }
    def check_runs_status(owner, repo, ref)
      data = get("/repos/#{owner}/#{repo}/commits/#{ref}/check-runs")
      return {} unless data.is_a?(Hash)

      runs = data["check_runs"] || []
      conclusions = runs.select { |r| r["status"] == "completed" }.map { |r| r["conclusion"] }
      in_progress = runs.count { |r| r["status"] != "completed" }

      { total_count: data["total_count"].to_i, conclusions: conclusions, in_progress_count: in_progress }
    rescue => e
      Rails.logger.error "[GitHub API] check_runs_status error: #{e.message}"
      {}
    end

    def merge_pr(owner, repo, pr_number, merge_method: "squash")
      result = http_put_json(
        "https://api.github.com/repos/#{owner}/#{repo}/pulls/#{pr_number}/merge",
        { merge_method: merge_method },
        headers
      )
      if result.is_a?(Hash) && result["merged"]
        { success: true, sha: result["sha"] }
      else
        { success: false, error: result[:error] || result["message"] || "Merge failed" }
      end
    rescue => e
      Rails.logger.error "[GitHub API] merge_pr error: #{e.message}"
      { success: false, error: e.message }
    end

    # Convert a draft PR to ready for review (required before merging)
    def mark_pr_ready(owner, repo, pr_number)
      patch("/repos/#{owner}/#{repo}/pulls/#{pr_number}", { draft: false })
    rescue => e
      Rails.logger.warn "[GitHub API] mark_pr_ready error: #{e.message}"
    end

    private

    def headers
      { "Authorization" => "Bearer #{@token}", "Accept" => "application/vnd.github+json" }
    end

    def http_json(url, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      headers.each { |k, v| req[k] = v }
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      Rails.logger.info "[GitHub API] GET #{uri.path} status=#{res.code}"
      JSON.parse(res.body)
    end

    def http_post_json(url, body, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body ? JSON.generate(body) : ""
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      Rails.logger.info "[GitHub API] POST #{uri.path} status=#{res.code}"
      return { error: "HTTP #{res.code}" } if res.code.to_i >= 400
      JSON.parse(res.body) rescue {}
    end

    def http_put_json(url, body, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Put.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body ? JSON.generate(body) : ""
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      Rails.logger.info "[GitHub API] PUT #{uri.path} status=#{res.code}"
      return { error: "HTTP #{res.code}" } if res.code.to_i >= 400
      JSON.parse(res.body) rescue {}
    end

    def http_patch_json(url, body, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Patch.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body ? JSON.generate(body) : ""
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      Rails.logger.info "[GitHub API] PATCH #{uri.path} status=#{res.code}"
      if res.code.to_i >= 400
        gh_message = (JSON.parse(res.body)["message"] rescue nil)
        Rails.logger.error "[GitHub API] PATCH #{uri.path} error: #{res.body.first(300)}"
        return { error: gh_message || "HTTP #{res.code}" }
      end
      JSON.parse(res.body) rescue {}
    end
  end
end
