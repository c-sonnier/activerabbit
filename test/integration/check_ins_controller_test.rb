# frozen_string_literal: true

require "test_helper"

class CheckInsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  test "requires authentication for index" do
    sign_out @user
    get check_ins_path
    assert_redirected_to new_user_session_path
  end

  test "GET index succeeds" do
    get check_ins_path
    assert_response :success
  end

  test "GET index scoped to project when using slug" do
    other = CheckIn.create!(
      account: @account,
      project: projects(:with_slack),
      identifier: "otherproj_ci",
      description: "Other project CI",
      kind: "cron",
      heartbeat_interval_seconds: 600,
      timezone: "UTC",
      enabled: true
    )
    get "/#{@project.slug}/check_ins"
    assert_response :success
    body = response.body
    assert_includes body, check_ins(:healthy).description
    refute_includes body, "Other project CI"
  ensure
    other&.destroy
  end

  test "GET new check-in form" do
    get new_check_in_path
    assert_response :success
  end

  test "POST create check-in" do
    assert_difference -> { CheckIn.count }, 1 do
      post check_ins_path, params: {
        check_in: {
          project_id: @project.id,
          description: "Integration CI",
          kind: "cron",
          heartbeat_interval_seconds: 3600,
          enabled: "1"
        }
      }
    end
    assert_redirected_to %r{/check_ins/\d+\z}
    follow_redirect!
    assert_response :success
  end
end
