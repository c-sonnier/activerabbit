# frozen_string_literal: true

require "test_helper"

class ApiCheckInsTest < ActionDispatch::IntegrationTest
  setup do
    @check_in = check_ins(:api_ok)
    @token = api_tokens(:default)
    @api_headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => @token.token }
    ActsAsTenant.without_tenant { CheckInPing.delete_all }
  end

  test "GET /api/v1/check_in/:token returns ok and records ping" do
    assert_difference -> { CheckInPing.where(check_in_id: @check_in.id).count }, 1 do
      get "/api/v1/check_in/#{@check_in.identifier}"
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    assert json["last_seen_at"].present?

    @check_in.reload
    assert @check_in.last_seen_at.present?
  end

  test "POST /api/v1/check_in/:token behaves like GET" do
    assert_difference -> { CheckInPing.where(check_in_id: @check_in.id).count }, 1 do
      post "/api/v1/check_in/#{@check_in.identifier}"
    end
    assert_response :success
  end

  test "unknown token returns not_found" do
    get "/api/v1/check_in/nonexistent_token_xyz"
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json["status"]
  end

  test "disabled check-in returns not_found" do
    token = check_ins(:disabled).identifier
    get "/api/v1/check_in/#{token}"
    assert_response :not_found
  end

  # POST /api/v1/cron/check_ins (project token + monitor slug)

  test "cron check-in requires authentication" do
    post "/api/v1/cron/check_ins",
         params: { slug: @check_in.slug, status: "ok" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
  end

  test "POST cron check_ins ok records ping" do
    assert @check_in.slug.present?

    assert_difference -> { CheckInPing.where(check_in_id: @check_in.id).count }, 1 do
      post "/api/v1/cron/check_ins",
           params: { slug: @check_in.slug, status: "ok" }.to_json,
           headers: @api_headers
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    assert json["last_seen_at"].present?
  end

  test "POST cron check_ins in_progress sets run_started_at" do
    freeze_time do
      post "/api/v1/cron/check_ins",
           params: { slug: @check_in.slug, status: "in_progress" }.to_json,
           headers: @api_headers
      assert_response :success
      @check_in.reload
      assert_equal Time.current, @check_in.run_started_at
    end
  end

  test "POST cron check_ins ok clears run_started_at" do
    @check_in.update_column(:run_started_at, 1.hour.ago)
    post "/api/v1/cron/check_ins",
         params: { slug: @check_in.slug, status: "ok" }.to_json,
         headers: @api_headers
    assert_response :success
    @check_in.reload
    assert_nil @check_in.run_started_at
  end

  test "POST cron check_ins error records error ping and optional message" do
    assert_difference -> { CheckInPing.where(check_in_id: @check_in.id, status: "error").count }, 1 do
      post "/api/v1/cron/check_ins",
           params: { slug: @check_in.slug, status: "error", message: "job failed" }.to_json,
           headers: @api_headers
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    @check_in.reload
    assert_nil @check_in.run_started_at
    assert_equal "missed", @check_in.last_status
  end

  test "POST cron check_ins missing slug is bad_request" do
    post "/api/v1/cron/check_ins",
         params: { status: "ok" }.to_json,
         headers: @api_headers
    assert_response :bad_request
  end

  test "POST cron check_ins invalid status is bad_request" do
    post "/api/v1/cron/check_ins",
         params: { slug: @check_in.slug, status: "nope" }.to_json,
         headers: @api_headers
    assert_response :bad_request
  end

  test "POST cron check_ins unknown slug is not_found" do
    post "/api/v1/cron/check_ins",
         params: { slug: "does_not_exist", status: "ok" }.to_json,
         headers: @api_headers
    assert_response :not_found
  end
end
