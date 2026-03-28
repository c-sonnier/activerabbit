require "test_helper"

class ReplayStorageTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Minimal fake S3 response objects
  # ---------------------------------------------------------------------------

  class FakeBody
    def initialize(content)
      @content = content
    end

    def read
      @content
    end
  end

  class FakeGetResponse
    attr_reader :body

    def initialize(content)
      @body = FakeBody.new(content)
    end
  end

  class FakePresigner
    def presigned_url(_operation, bucket:, key:, expires_in: 3600)
      "https://#{bucket}.example.com/#{key}?X-Expires=#{expires_in}"
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def mock_client
    @mock_client ||= Minitest::Mock.new
  end

  def storage
    @storage ||= ReplayStorage.new(client: mock_client)
  end

  # ===========================================================================
  # upload
  # ===========================================================================

  test "upload returns success hash on success" do
    data = "compressed_bytes"
    key  = "replays/1/1/abc123"

    mock_client.expect(:put_object, nil) do |**kwargs|
      kwargs[:bucket] == ReplayStorage::BUCKET && kwargs[:key] == key && kwargs[:body] == data
    end

    result = storage.upload(key: key, data: data)

    assert result[:success]
    assert_equal key,            result[:key]
    assert_equal data.bytesize,  result[:size]
    mock_client.verify
  end

  test "upload returns failure hash on S3 error" do
    key  = "replays/1/1/abc123"
    data = "compressed_bytes"

    mock_client.expect(:put_object, nil) do |**_kwargs|
      raise Aws::S3::Errors::ServiceError.new(nil, "Upload failed")
    end

    result = storage.upload(key: key, data: data)

    refute result[:success]
    assert result[:error].present?
  end

  # ===========================================================================
  # download
  # ===========================================================================

  test "download returns body string on success" do
    key     = "replays/1/1/abc123"
    content = "raw replay data"

    mock_client.expect(:get_object, FakeGetResponse.new(content)) do |**kwargs|
      kwargs[:bucket] == ReplayStorage::BUCKET && kwargs[:key] == key
    end

    result = storage.download(key: key)

    assert_equal content, result
    mock_client.verify
  end

  test "download raises on S3 error" do
    key = "replays/1/1/missing"

    mock_client.expect(:get_object, nil) do |**_kwargs|
      raise Aws::S3::Errors::ServiceError.new(nil, "Not found")
    end

    assert_raises(Aws::S3::Errors::ServiceError) do
      storage.download(key: key)
    end
  end

  # ===========================================================================
  # delete
  # ===========================================================================

  test "delete returns true on success" do
    key = "replays/1/1/abc123"

    mock_client.expect(:delete_object, nil) do |**kwargs|
      kwargs[:bucket] == ReplayStorage::BUCKET && kwargs[:key] == key
    end

    assert storage.delete(key: key)
    mock_client.verify
  end

  test "delete returns false on S3 error" do
    key = "replays/1/1/abc123"

    mock_client.expect(:delete_object, nil) do |**_kwargs|
      raise Aws::S3::Errors::ServiceError.new(nil, "Delete failed")
    end

    refute storage.delete(key: key)
  end

  # ===========================================================================
  # exists?
  # ===========================================================================

  test "exists? returns true when object is found" do
    key = "replays/1/1/abc123"

    mock_client.expect(:head_object, OpenStruct.new) do |**kwargs|
      kwargs[:bucket] == ReplayStorage::BUCKET && kwargs[:key] == key
    end

    assert storage.exists?(key: key)
    mock_client.verify
  end

  test "exists? returns false when object is not found" do
    key = "replays/1/1/missing"

    mock_client.expect(:head_object, nil) do |**_kwargs|
      raise Aws::S3::Errors::NotFound.new(nil, "Not found")
    end

    refute storage.exists?(key: key)
  end

  test "exists? returns false on generic S3 error" do
    key = "replays/1/1/broken"

    mock_client.expect(:head_object, nil) do |**_kwargs|
      raise Aws::S3::Errors::ServiceError.new(nil, "Internal error")
    end

    refute storage.exists?(key: key)
  end

  # ===========================================================================
  # presigned_url
  # ===========================================================================

  test "presigned_url returns a URL string" do
    key = "replays/1/1/abc123"

    # Stub Aws::S3::Presigner to avoid real credential requirements
    fake_presigner = FakePresigner.new
    Aws::S3::Presigner.stub(:new, fake_presigner) do
      url = storage.presigned_url(key: key)
      assert url.is_a?(String)
      assert url.start_with?("https://")
      assert_includes url, key
    end
  end

  test "presigned_url respects custom expires_in" do
    key = "replays/1/1/abc123"

    fake_presigner = FakePresigner.new
    Aws::S3::Presigner.stub(:new, fake_presigner) do
      url = storage.presigned_url(key: key, expires_in: 7200)
      assert_includes url, "7200"
    end
  end
end
