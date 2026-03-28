require "test_helper"

class ReplaysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    @replay = replays(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # ===========================================================================
  # Index
  # ===========================================================================

  test "GET replays index renders successfully" do
    get project_replays_path(@project.slug)
    assert_response :success
  end

  test "GET replays index requires authentication" do
    sign_out @user
    get project_replays_path(@project.slug)
    assert_redirected_to new_user_session_path
  end

  test "GET replays index only shows ready replays" do
    get project_replays_path(@project.slug)
    assert_response :success
    # pending_replay should not appear in the list
    refute_match replays(:pending_replay).replay_id, response.body
  end

  test "GET replays index shows replay duration" do
    get project_replays_path(@project.slug)
    assert_response :success
    # default replay has duration_ms: 30000 = 30s
    assert_match(/30s/, response.body)
  end

  # ===========================================================================
  # Show
  # ===========================================================================

  test "GET replay show renders successfully" do
    get project_replay_path(@project.slug, @replay)
    assert_response :success
  end

  test "GET replay show displays session duration" do
    get project_replay_path(@project.slug, @replay)
    assert_response :success
    # 30000ms = 30s (no minutes prefix when under 60s)
    assert_match(/30s/, response.body)
  end

  test "GET replay show displays viewport dimensions" do
    @replay.update!(viewport_width: 1920, viewport_height: 1080)
    get project_replay_path(@project.slug, @replay)
    assert_match(/1920/, response.body)
    assert_match(/1080/, response.body)
  end

  test "GET replay show displays environment badge" do
    get project_replay_path(@project.slug, @replay)
    assert_match(/production/, response.body)
  end

  test "GET replay show renders player controls" do
    get project_replay_path(@project.slug, @replay)
    assert_select "#replay-controls", 1
    assert_select "#replay-progress", 1
    assert_select "#replay-play-btn", 1
  end

  test "GET replay show renders speed buttons" do
    get project_replay_path(@project.slug, @replay)
    assert_select ".replay-speed-btn", 4  # 1x, 2x, 4x, 8x
  end

  test "GET replay show renders event density bar" do
    get project_replay_path(@project.slug, @replay)
    assert_select "#event-density-bar", 1
  end

  test "GET replay show renders skip overlay element" do
    get project_replay_path(@project.slug, @replay)
    assert_select "#replay-skip-overlay", 1
  end

  test "GET replay show renders technical details" do
    get project_replay_path(@project.slug, @replay)
    assert_match(/Events/, response.body)
    assert_match(/#{@replay.event_count}/, response.body)
  end

  test "GET replay show renders session details" do
    get project_replay_path(@project.slug, @replay)
    assert_match(/Duration/, response.body)
    assert_match(/Environment/, response.body)
    assert_match(/Viewport/, response.body)
  end

  test "GET replay show requires authentication" do
    sign_out @user
    get project_replay_path(@project.slug, @replay)
    assert_redirected_to new_user_session_path
  end

  # ===========================================================================
  # Player progress bar uses real duration
  # ===========================================================================

  test "GET replay show sets progress bar max to duration_ms" do
    get project_replay_path(@project.slug, @replay)
    assert_select "#replay-progress[max='#{@replay.duration_ms}']"
  end

  test "GET replay show includes totalMs variable in script" do
    get project_replay_path(@project.slug, @replay)
    assert_match(/var serverDurationMs = #{@replay.duration_ms}/, response.body)
  end

  test "GET replay show includes skip inactive config" do
    get project_replay_path(@project.slug, @replay)
    assert_match(/skipInactive: true/, response.body)
  end

  test "GET replay show includes inactivity threshold" do
    get project_replay_path(@project.slug, @replay)
    assert_match(/INACTIVE_THRESHOLD_MS = 5000/, response.body)
  end
end
