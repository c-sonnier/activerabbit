require "test_helper"

class ApiLogsTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:default)
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
        "Authorization" => "Bearer #{@api_token.token}"
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
        "Authorization" => "Bearer #{@api_token.token}"
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
        "Authorization" => "Bearer #{@api_token.token}"
      }

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/logs requires authentication" do
    post "/api/v1/logs",
      params: { logs: [{ message: "test" }] }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end
end
