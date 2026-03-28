require "test_helper"

class ReplayRecorderSetupTest < ActionDispatch::IntegrationTest
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

  # ===========================================================================
  # Setup page shows when no replays exist
  # ===========================================================================

  test "replays index shows setup instructions when no replays" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_response :success
    assert_match(/Set up Session Replay/, response.body)
  end

  test "setup shows ActiveRabbitReplay config object snippet" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/window\.ActiveRabbitReplay/, response.body)
  end

  test "setup snippet includes project token" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/#{@project.api_token}/, response.body)
  end

  test "setup shows replaysSessionSampleRate config" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/replaysSessionSampleRate/, response.body)
  end

  test "setup shows replaysOnErrorSampleRate config" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/replaysOnErrorSampleRate/, response.body)
  end

  test "setup shows privacy options" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/maskAllInputs/, response.body)
    assert_match(/maskAllText/, response.body)
    assert_match(/blockAllMedia/, response.body)
  end

  test "setup shows recorder.js script tag" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(%r{/replay/recorder\.js}, response.body)
  end

  test "setup shows configuration options table" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/Configuration options/, response.body)
    assert_match(/replaysSessionSampleRate/, response.body)
    assert_match(/replaysOnErrorSampleRate/, response.body)
    assert_match(/blockClass/, response.body)
    assert_match(/maskTextClass/, response.body)
    assert_match(/flushInterval/, response.body)
  end

  test "setup shows sampling recommendation for high-traffic sites" do
    Replay.where(project: @project).delete_all

    get project_replays_path(@project.slug)
    assert_match(/high-traffic/, response.body)
  end

  # ===========================================================================
  # Setup page hidden when replays exist
  # ===========================================================================

  test "replays index shows replay list instead of setup when replays exist" do
    get project_replays_path(@project.slug)
    assert_response :success
    assert_match(/Recent Replays/, response.body)
  end

  # ===========================================================================
  # Static recorder.js file
  # ===========================================================================

  test "recorder.js exists as static file" do
    path = Rails.root.join("public", "replay", "recorder.js")
    assert File.exist?(path), "public/replay/recorder.js should exist"
  end

  test "recorder.js reads data-token attribute" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/data-token/, js)
  end

  test "recorder.js reads ActiveRabbitReplay config" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/window\.ActiveRabbitReplay/, js)
  end

  test "recorder.js supports replaysSessionSampleRate" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/replaysSessionSampleRate/, js)
  end

  test "recorder.js supports replaysOnErrorSampleRate" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/replaysOnErrorSampleRate/, js)
  end

  test "recorder.js masks inputs by default" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/maskAllInputs/, js)
    assert_match(/password:\s*true/, js)
  end

  test "recorder.js listens for errors" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/window\.addEventListener.*error/, js)
    assert_match(/unhandledrejection/, js)
  end

  test "recorder.js sends trigger_type field" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(/trigger_type/, js)
  end

  test "recorder.js loads rrweb from same origin" do
    js = File.read(Rails.root.join("public", "replay", "recorder.js"))
    assert_match(%r{origin.*rrweb\.min\.js}, js)
    # Should NOT reference cdn.jsdelivr.net
    refute_match(/cdn\.jsdelivr\.net/, js)
  end

  test "rrweb.min.js exists as static file" do
    path = Rails.root.join("public", "rrweb.min.js")
    assert File.exist?(path), "public/rrweb.min.js should exist"
  end
end
