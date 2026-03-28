require "test_helper"

class ReplayCleanupJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
  end

  # ===========================================================================
  # Expired replays
  # ===========================================================================

  test "updates status to expired for expired ready replays" do
    expired = replays(:expired_replay)
    assert_equal "ready", expired.status

    mock_storage = Minitest::Mock.new
    mock_storage.expect(:delete, true, []) do |key:|
      key == expired.storage_key
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    assert_equal "expired", expired.reload.status
    mock_storage.verify
  end

  test "deletes storage for expired replays with a storage_key" do
    expired    = replays(:expired_replay)
    deleted_keys = []

    mock_storage = Object.new
    mock_storage.define_singleton_method(:delete) do |key:|
      deleted_keys << key
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    assert_includes deleted_keys, expired.storage_key
  end

  test "skips storage deletion for expired replays without a storage_key" do
    expired = replays(:expired_replay)
    expired.update_column(:storage_key, nil)

    delete_called = false
    mock_storage  = Object.new
    mock_storage.define_singleton_method(:delete) do |key:|
      delete_called = true
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    refute delete_called, "delete should not be called when storage_key is nil"
    assert_equal "expired", expired.reload.status
  end

  # ===========================================================================
  # Non-expired replays are untouched
  # ===========================================================================

  test "does not touch non-expired ready replays" do
    active = replays(:default)
    assert_equal "ready", active.status

    mock_storage = Object.new
    mock_storage.define_singleton_method(:delete) { |key:| true }

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    assert_equal "ready", active.reload.status
  end

  test "does not touch pending replays even if retention_until is past" do
    pending_replay = replays(:pending_replay)
    # Force retention_until into the past without changing status
    pending_replay.update_column(:retention_until, 2.days.ago)

    deleted_keys = []
    mock_storage = Object.new
    mock_storage.define_singleton_method(:delete) do |key:|
      deleted_keys << key
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    # pending_replay has no storage_key, so even if it were picked up
    # no delete would be called for it. More importantly, its status must
    # not become "expired" since the job only targets status="ready".
    assert_equal "pending", pending_replay.reload.status
  end

  # ===========================================================================
  # Idempotency — already-expired rows are ignored
  # ===========================================================================

  test "does not re-process replays already marked expired" do
    expired = replays(:expired_replay)
    expired.update_column(:status, "expired")

    delete_called = false
    mock_storage  = Object.new
    mock_storage.define_singleton_method(:delete) do |key:|
      delete_called = true
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    refute delete_called, "delete should not be called for already-expired replay"
  end

  # ===========================================================================
  # Bulk behaviour
  # ===========================================================================

  test "processes multiple expired replays in one run" do
    second_expired = Replay.create!(
      account:         @account,
      project:         @project,
      replay_id:       SecureRandom.uuid,
      session_id:      SecureRandom.uuid,
      status:          "ready",
      started_at:      45.days.ago,
      duration_ms:     10_000,
      storage_key:     "replays/1/1/second-expired",
      retention_until: 2.days.ago,
      uploaded_at:     45.days.ago
    )

    expired       = replays(:expired_replay)
    deleted_keys  = []

    mock_storage = Object.new
    mock_storage.define_singleton_method(:delete) do |key:|
      deleted_keys << key
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayCleanupJob.new.perform
    end

    assert_includes deleted_keys, expired.storage_key
    assert_includes deleted_keys, second_expired.storage_key
    assert_equal "expired", expired.reload.status
    assert_equal "expired", second_expired.reload.status
  end
end
