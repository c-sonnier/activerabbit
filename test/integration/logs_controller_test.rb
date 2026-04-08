# frozen_string_literal: true

require "test_helper"

class LogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "GET /logs requires authentication" do
    sign_out @user
    get logs_path
    assert_redirected_to new_user_session_path
  end

  test "GET /logs loads successfully" do
    get logs_path
    assert_response :success
  end

  test "GET /projects/:project_id/logs scopes to project" do
    get project_logs_path(@project)
    assert_response :success
  end

  test "GET /logs/:id shows entry" do
    entry = log_entries(:error_log)
    get log_entry_path(entry)
    assert_response :success
  end

  test "GET /logs with level filter" do
    get logs_path, params: { level: "error" }
    assert_response :success
  end

  test "GET /logs with time range" do
    get logs_path, params: { range: "1h" }
    assert_response :success
  end

  test "GET /logs with search query" do
    get logs_path, params: { q: "level:error" }
    assert_response :success
  end
end
