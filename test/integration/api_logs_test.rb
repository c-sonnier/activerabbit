require "test_helper"

class ApiLogsTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:default)
    @account = accounts(:default)
    @api_token = api_tokens(:default)
  end

  test "POST /api/v1/logs accepts log entries" do
    post "/api/v1/logs",
      params: {
        logs: [
          { level: 2, message: "Test log entry", environment: "production" }
        ]
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Project-Token" => @api_token.token
      }

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "accepted", json["status"]
  end

  test "POST /api/v1/logs rejects empty batch" do
    post "/api/v1/logs",
      params: { logs: [] }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Project-Token" => @api_token.token
      }

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/logs rejects entries without message" do
    post "/api/v1/logs",
      params: {
        logs: [{ level: 2 }]
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Project-Token" => @api_token.token
      }

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/logs requires authentication" do
    post "/api/v1/logs",
      params: { logs: [{ message: "test" }] }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "POST /api/v1/logs returns 429 when log storage quota is full" do
    @account.update!(cached_log_bytes_used: ResourceQuotas::LOG_BYTES_QUOTA)

    post "/api/v1/logs",
      params: {
        logs: [{ message: "blocked", environment: "production" }]
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Project-Token" => @api_token.token
      }

    assert_response :too_many_requests
    json = JSON.parse(response.body)
    assert_equal "quota_exceeded", json["error"]
    assert_match(/storage quota/i, json["message"])
  ensure
    @account.update!(cached_log_bytes_used: 0)
  end

  test "POST /api/v1/logs rejects batch larger than 1000 entries" do
    logs = (1..1001).map { |i| { message: "line #{i}", environment: "production" } }

    post "/api/v1/logs",
      params: { logs: logs }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Project-Token" => @api_token.token
      }

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/logs accepts entries key as alias for logs" do
    post "/api/v1/logs",
      params: {
        entries: [{ message: "via entries key", environment: "production" }]
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Project-Token" => @api_token.token
      }

    assert_response :accepted
  end
end
