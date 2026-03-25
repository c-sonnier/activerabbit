require "test_helper"

class ReplayTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @replay  = replays(:default)
  end

  # ===========================================================================
  # Validations
  # ===========================================================================

  test "valid replay is valid" do
    assert @replay.valid?
  end

  test "replay_id is required" do
    @replay.replay_id = nil
    refute @replay.valid?
    assert_includes @replay.errors[:replay_id], "can't be blank"
  end

  test "session_id is required" do
    @replay.session_id = nil
    refute @replay.valid?
    assert_includes @replay.errors[:session_id], "can't be blank"
  end

  test "started_at is required" do
    @replay.started_at = nil
    refute @replay.valid?
    assert_includes @replay.errors[:started_at], "can't be blank"
  end

  test "duration_ms is required" do
    @replay.duration_ms = nil
    refute @replay.valid?
    assert_includes @replay.errors[:duration_ms], "can't be blank"
  end

  test "duration_ms must be greater than 0" do
    @replay.duration_ms = 0
    refute @replay.valid?
    assert_includes @replay.errors[:duration_ms], "must be greater than 0"
  end

  test "duration_ms cannot be negative" do
    @replay.duration_ms = -1
    refute @replay.valid?
    assert_includes @replay.errors[:duration_ms], "must be greater than 0"
  end

  test "invalid status is rejected" do
    @replay.status = "unknown_status"
    refute @replay.valid?
    assert_includes @replay.errors[:status], "is not included in the list"
  end

  test "all valid statuses are accepted" do
    %w[pending processing ready failed expired].each do |status|
      @replay.status = status
      assert @replay.valid?, "Expected status '#{status}' to be valid"
    end
  end

  test "event_count must be greater than 0 when present" do
    @replay.event_count = 0
    refute @replay.valid?
    assert_includes @replay.errors[:event_count], "must be greater than 0"
  end

  test "event_count can be nil" do
    @replay.event_count = nil
    assert @replay.valid?
  end

  test "compressed_size must be >= 0 when present" do
    @replay.compressed_size = -1
    refute @replay.valid?
    assert_includes @replay.errors[:compressed_size], "must be greater than or equal to 0"
  end

  test "uncompressed_size must be >= 0 when present" do
    @replay.uncompressed_size = -1
    refute @replay.valid?
    assert_includes @replay.errors[:uncompressed_size], "must be greater than or equal to 0"
  end

  # ===========================================================================
  # Scopes
  # ===========================================================================

  test "ready scope returns only ready replays" do
    ready_replays = Replay.ready
    assert ready_replays.all? { |r| r.status == "ready" }
    assert_includes ready_replays, replays(:default)
  end

  test "ready scope excludes pending replays" do
    refute_includes Replay.ready, replays(:pending_replay)
  end

  test "expired scope returns replays past retention_until" do
    expired_replays = Replay.expired
    assert_includes expired_replays, replays(:expired_replay)
  end

  test "expired scope excludes replays with future retention_until" do
    refute_includes Replay.expired, replays(:default)
  end

  test "with_issue scope returns replays linked to an issue" do
    issue = issues(:open_issue)
    @replay.update!(issue: issue)
    assert_includes Replay.with_issue, @replay
  end

  test "with_issue scope excludes replays without an issue" do
    @replay.update!(issue: nil)
    refute_includes Replay.with_issue, @replay
  end

  test "recent scope orders by created_at descending" do
    replays = Replay.recent
    times = replays.map(&:created_at)
    assert_equal times.sort.reverse, times
  end

  # ===========================================================================
  # expired?
  # ===========================================================================

  test "expired? returns true when retention_until is in the past" do
    assert replays(:expired_replay).expired?
  end

  test "expired? returns false when retention_until is in the future" do
    refute replays(:default).expired?
  end

  test "expired? returns false when retention_until is nil" do
    @replay.retention_until = nil
    refute @replay.expired?
  end

  # ===========================================================================
  # storage_path
  # ===========================================================================

  test "storage_path returns correct format" do
    expected = "replays/#{@replay.account_id}/#{@replay.project_id}/#{@replay.replay_id}"
    assert_equal expected, @replay.storage_path
  end

  # ===========================================================================
  # mark_ready!
  # ===========================================================================

  test "mark_ready! sets status to ready" do
    replay = replays(:pending_replay)
    replay.mark_ready!(
      storage_key:       "replays/1/1/test-key",
      compressed_size:   1024,
      uncompressed_size: 4096,
      event_count:       50,
      checksum_sha256:   "deadbeef"
    )
    assert_equal "ready", replay.reload.status
  end

  test "mark_ready! stores all provided fields" do
    replay = replays(:pending_replay)
    replay.mark_ready!(
      storage_key:       "replays/1/1/test-key",
      compressed_size:   1024,
      uncompressed_size: 4096,
      event_count:       50,
      checksum_sha256:   "deadbeef"
    )
    replay.reload
    assert_equal "replays/1/1/test-key", replay.storage_key
    assert_equal 1024,     replay.compressed_size
    assert_equal 4096,     replay.uncompressed_size
    assert_equal 50,       replay.event_count
    assert_equal "deadbeef", replay.checksum_sha256
  end

  test "mark_ready! sets uploaded_at to current time" do
    replay = replays(:pending_replay)
    freeze_time = Time.current
    travel_to freeze_time do
      replay.mark_ready!(
        storage_key:       "replays/1/1/test-key",
        compressed_size:   512,
        uncompressed_size: 2048,
        event_count:       10,
        checksum_sha256:   "abc"
      )
    end
    assert_in_delta freeze_time.to_i, replay.reload.uploaded_at.to_i, 1
  end

  # ===========================================================================
  # mark_failed!
  # ===========================================================================

  test "mark_failed! sets status to failed" do
    replay = replays(:pending_replay)
    replay.mark_failed!
    assert_equal "failed", replay.reload.status
  end
end
