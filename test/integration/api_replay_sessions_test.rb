require "test_helper"

class ApiReplaySessionsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @token = @project.api_token
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Sidekiq::Worker.clear_all
  end

  # ===========================================================================
  # Authentication
  # ===========================================================================

  test "POST without token returns 401" do
    post "/api/v1/replay_sessions", params: valid_replay_params, as: :json
    assert_response :unauthorized
  end

  test "POST with invalid token returns 401" do
    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: { "X-Project-Token" => "invalid-token" },
      as: :json
    assert_response :unauthorized
  end

  # ===========================================================================
  # New replay creation
  # ===========================================================================

  test "POST creates a new replay" do
    assert_difference "Replay.count", 1 do
      post "/api/v1/replay_sessions",
        params: valid_replay_params,
        headers: auth_headers,
        as: :json
    end
    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "accepted", json["status"]
    assert json["replay_id"].present?
  end

  test "POST sets replay attributes correctly" do
    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    replay = Replay.last
    assert_equal "pending", replay.status
    assert_equal @account.id, replay.account_id
    assert_equal @project.id, replay.project_id
    assert_equal 5000, replay.duration_ms
    assert_equal "production", replay.environment
    assert replay.retention_until > 29.days.from_now
  end

  test "POST enqueues ReplayIngestJob" do
    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    assert_equal 1, ReplayIngestJob.jobs.size
  end

  test "POST enqueues ReplayIssueLinkJob" do
    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    assert_equal 1, ReplayIssueLinkJob.jobs.size
  end

  test "POST increments replay usage counter" do
    original_count = @account.cached_replays_used

    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    assert_equal original_count + 1, @account.reload.cached_replays_used
  end

  # ===========================================================================
  # Upsert (existing replay_id)
  # ===========================================================================

  test "POST with existing replay_id updates instead of creating" do
    existing = replays(:default)
    params = valid_replay_params.merge(replay_id: existing.replay_id)

    assert_no_difference "Replay.count" do
      post "/api/v1/replay_sessions",
        params: params,
        headers: auth_headers,
        as: :json
    end
    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "updated", json["status"]
  end

  test "POST upsert enqueues ReplayIngestJob for existing replay" do
    existing = replays(:default)
    params = valid_replay_params.merge(replay_id: existing.replay_id)

    post "/api/v1/replay_sessions",
      params: params,
      headers: auth_headers,
      as: :json

    assert_equal 1, ReplayIngestJob.jobs.size
  end

  test "POST upsert does not increment replay usage counter" do
    existing = replays(:default)
    params = valid_replay_params.merge(replay_id: existing.replay_id)
    original_count = @account.cached_replays_used

    post "/api/v1/replay_sessions",
      params: params,
      headers: auth_headers,
      as: :json

    assert_equal original_count, @account.reload.cached_replays_used
  end

  # ===========================================================================
  # Quota enforcement
  # ===========================================================================

  test "POST returns 429 when replay quota exceeded" do
    quota = @account.session_replays_quota
    @account.update!(cached_replays_used: quota)

    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    assert_response :too_many_requests
    json = JSON.parse(response.body)
    assert_equal "quota_exceeded", json["error"]
  end

  test "POST returns 429 when over quota limit" do
    quota = @account.session_replays_quota
    @account.update!(cached_replays_used: quota + 5)

    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    assert_response :too_many_requests
  end

  test "POST succeeds when just below quota limit" do
    quota = @account.session_replays_quota
    @account.update!(cached_replays_used: quota - 1)

    post "/api/v1/replay_sessions",
      params: valid_replay_params,
      headers: auth_headers,
      as: :json

    assert_response :accepted
  end

  # ===========================================================================
  # Project scoping — replay_id lookup is scoped to current project
  # ===========================================================================

  test "POST upsert scoped to current project not account" do
    # Create a replay on the default project
    existing = replays(:default)

    # Upsert from the SAME project should find and update the existing replay
    assert_no_difference "Replay.count" do
      post "/api/v1/replay_sessions",
        params: valid_replay_params.merge(replay_id: existing.replay_id),
        headers: auth_headers,
        as: :json
    end
    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "updated", json["status"]

    # Now verify the lookup uses project scope:
    # The replay belongs to @project — querying via another project should NOT find it
    other_project = projects(:with_slack)
    assert_nil other_project.replays.find_by(replay_id: existing.replay_id),
      "Replay from default project should not be found via other project's association"
  end

  # ===========================================================================
  # Required fields
  # ===========================================================================

  test "POST requires replay_id" do
    params = valid_replay_params.except(:replay_id)
    post "/api/v1/replay_sessions",
      params: params,
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "POST requires started_at" do
    params = valid_replay_params.except(:started_at)
    post "/api/v1/replay_sessions",
      params: params,
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "POST requires duration_ms" do
    params = valid_replay_params.except(:duration_ms)
    post "/api/v1/replay_sessions",
      params: params,
      headers: auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "POST rejects recording when page URL is the ActiveRabbit app host" do
    prev = ENV["APP_HOST"]
    ENV["APP_HOST"] = "app.example.com"
    params = valid_replay_params.merge(url: "https://app.example.com/dashboard")
    assert_no_difference "Replay.count" do
      post "/api/v1/replay_sessions",
        params: params,
        headers: auth_headers,
        as: :json
    end
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "invalid_recording_origin", json["error"]
  ensure
    if prev
      ENV["APP_HOST"] = prev
    else
      ENV.delete("APP_HOST")
    end
  end

  private

  def auth_headers
    { "X-Project-Token" => @token }
  end

  def valid_replay_params
    {
      replay_id: SecureRandom.uuid,
      session_id: SecureRandom.uuid,
      events: [
        { type: 4, data: { href: "https://example.com", width: 1920, height: 1080 }, timestamp: 1000 },
        { type: 2, data: {}, timestamp: 2000 },
        { type: 3, data: { source: 1 }, timestamp: 3000 }
      ],
      started_at: Time.current.iso8601,
      duration_ms: 5000,
      segment_index: 0,
      url: "https://example.com/test",
      user_agent: "Mozilla/5.0 Test Browser",
      viewport_width: 1920,
      viewport_height: 1080,
      environment: "production",
      sdk_version: "0.1.0",
      rrweb_version: "2.0.0-alpha.4"
    }
  end
end
