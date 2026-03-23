# frozen_string_literal: true

module Github
  # Fetches repository information for a GitHub App installation
  class InstallationService
    def initialize(installation_id)
      @installation_id = installation_id
      @app_id = ENV["AR_GH_APP_ID"]
      @app_pk = Github::TokenManager.resolve_env_private_key
    end

    def fetch_installation_info
      return { success: false, error: "GitHub App not configured (missing AR_GH_APP_ID or AR_GH_APP_PK)" } unless configured?

      token = generate_installation_token
      return { success: false, error: "Failed to generate installation token" } unless token

      # Fetch repositories accessible to this installation
      repos = fetch_installation_repos(token)
      return { success: false, error: "No repositories found for this installation" } if repos.empty?

      # Use the first repository (most common case for single-repo installations)
      repo = repos.first
      owner = repo["owner"]["login"]
      repo_name = repo["name"]
      full_name = "#{owner}/#{repo_name}"
      default_branch = repo["default_branch"] || "main"

      {
        success: true,
        repository: full_name,
        default_branch: default_branch,
        repositories: repos.map { |r| { full_name: r["full_name"], default_branch: r["default_branch"] } }
      }
    rescue => e
      Rails.logger.error "[Github::InstallationService] Error: #{e.message}"
      { success: false, error: e.message }
    end

    def self.app_install_url(project_id: nil)
      app_slug = ENV["AR_GH_APP_SLUG"] || "activerabbit"
      base_url = "https://github.com/apps/#{app_slug}/installations/new"

      if project_id
        "#{base_url}?state=#{project_id}"
      else
        base_url
      end
    end

    private

    def configured?
      @app_id.present? && @app_pk.present?
    end

    def generate_installation_token
      jwt = generate_app_jwt
      response = http_post_json(
        "https://api.github.com/app/installations/#{@installation_id}/access_tokens",
        nil,
        {
          "Authorization" => "Bearer #{jwt}",
          "Accept" => "application/vnd.github+json"
        }
      )
      response&.dig("token")
    end

    def generate_app_jwt
      require "openssl"
      require "jwt"
      private_key = OpenSSL::PKey::RSA.new(@app_pk)
      payload = {
        iat: Time.now.to_i - 60,
        exp: Time.now.to_i + (10 * 60),
        iss: @app_id.to_i
      }
      JWT.encode(payload, private_key, "RS256")
    end

    def fetch_installation_repos(token)
      response = http_get_json(
        "https://api.github.com/installation/repositories",
        {
          "Authorization" => "Bearer #{token}",
          "Accept" => "application/vnd.github+json"
        }
      )
      response&.dig("repositories") || []
    end

    def http_post_json(url, body, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body ? JSON.generate(body) : ""
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      JSON.parse(res.body) rescue {}
    end

    def http_get_json(url, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      headers.each { |k, v| req[k] = v }
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      JSON.parse(res.body) rescue {}
    end
  end
end
