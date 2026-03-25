require "test_helper"

class ReplayIngestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @replay  = replays(:pending_replay)

    # Raw rrweb-style events JSON (3 simple events)
    @raw_events_json = JSON.generate([
      { type: 0, timestamp: 1_000 },
      { type: 1, timestamp: 1_050 },
      { type: 2, timestamp: 1_100 }
    ])
  end

  # ===========================================================================
  # Status transitions
  # ===========================================================================

  test "sets status to processing then ready on successful upload" do
    status_during_upload = nil

    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: true, key: @replay.storage_path, size: 42 }) do |key:, data:|
      # Capture status at the moment upload is called
      status_during_upload = @replay.reload.status
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
    end

    assert_equal "processing", status_during_upload
    assert_equal "ready",      @replay.reload.status
    mock_storage.verify
  end

  test "calls mark_failed! when upload fails" do
    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: false, error: "S3 unavailable" }, []) do |**_kwargs|
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
    end

    assert_equal "failed", @replay.reload.status
    mock_storage.verify
  end

  # ===========================================================================
  # Compression and size fields
  # ===========================================================================

  test "stores compressed data and sets compressed_size on success" do
    uploaded_data = nil

    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: true, key: @replay.storage_path, size: 0 }) do |key:, data:|
      uploaded_data = data
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
    end

    @replay.reload
    expected_compressed = Zlib::Deflate.deflate(@raw_events_json)

    assert_equal expected_compressed.bytesize, @replay.compressed_size
    assert_equal @raw_events_json.bytesize,    @replay.uncompressed_size
  end

  test "sets event_count to the number of events in the JSON array" do
    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: true, key: @replay.storage_path, size: 10 }, []) do |**_kwargs|
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
    end

    assert_equal 3, @replay.reload.event_count
  end

  test "sets checksum_sha256 on successful upload" do
    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: true, key: @replay.storage_path, size: 10 }, []) do |**_kwargs|
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
    end

    compressed       = Zlib::Deflate.deflate(@raw_events_json)
    expected_checksum = Digest::SHA256.hexdigest(compressed)

    assert_equal expected_checksum, @replay.reload.checksum_sha256
  end

  # ===========================================================================
  # retention_until
  # ===========================================================================

  test "sets retention_until to 30 days from now on successful upload" do
    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: true, key: @replay.storage_path, size: 10 }, []) do |**_kwargs|
      true
    end

    expected_time = 30.days.from_now
    travel_to(Time.current) do
      ReplayStorage.stub(:client, mock_storage) do
        ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
      end
    end

    assert_in_delta expected_time.to_i, @replay.reload.retention_until.to_i, 5
  end

  test "does not set retention_until on failed upload" do
    original_retention = @replay.retention_until

    mock_storage = Minitest::Mock.new
    mock_storage.expect(:upload, { success: false, error: "Timeout" }, []) do |**_kwargs|
      true
    end

    ReplayStorage.stub(:client, mock_storage) do
      ReplayIngestJob.new.perform(@replay.id, @raw_events_json)
    end

    assert_equal original_retention, @replay.reload.retention_until
  end

  # ===========================================================================
  # Error handling
  # ===========================================================================

  test "raises ActiveRecord::RecordNotFound for unknown replay id" do
    assert_raises ActiveRecord::RecordNotFound do
      ReplayIngestJob.new.perform(999_999_999, @raw_events_json)
    end
  end
end
