# frozen_string_literal: true

require "aws-sdk-s3"

class ReplayStorage
  BUCKET      = ENV["R2_REPLAY_BUCKET"]
  ENDPOINT    = ENV["R2_REPLAY_ENDPOINT"]
  ACCESS_KEY  = ENV["R2_REPLAY_ACCESS_KEY_ID"]
  SECRET_KEY  = ENV["R2_REPLAY_SECRET_ACCESS_KEY"]
  REGION      = ENV.fetch("R2_REPLAY_REGION", "auto")

  def initialize(client: nil)
    @client = client || build_client
  end

  # PUT an object into R2.
  # Returns { success: true, key:, size: } or { success: false, error: }.
  def upload(key:, data:, content_type: "application/octet-stream")
    @client.put_object(
      bucket: BUCKET,
      key: key,
      body: data,
      content_type: content_type
    )
    { success: true, key: key, size: data.bytesize }
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "[ReplayStorage] upload failed for key=#{key}: #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  # GET an object from R2 and return its body as a String.
  # Raises on error so callers can decide how to handle missing replays.
  def download(key:)
    response = @client.get_object(bucket: BUCKET, key: key)
    response.body.read
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "[ReplayStorage] download failed for key=#{key}: #{e.class}: #{e.message}"
    raise
  end

  # DELETE an object from R2.
  # Returns true on success, false on error.
  def delete(key:)
    @client.delete_object(bucket: BUCKET, key: key)
    true
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "[ReplayStorage] delete failed for key=#{key}: #{e.class}: #{e.message}"
    false
  end

  # HEAD check — returns true if the object exists, false otherwise.
  def exists?(key:)
    @client.head_object(bucket: BUCKET, key: key)
    true
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
    false
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "[ReplayStorage] exists? failed for key=#{key}: #{e.class}: #{e.message}"
    false
  end

  # Generate a presigned GET URL valid for +expires_in+ seconds (default 1 hour).
  def presigned_url(key:, expires_in: 3600)
    presigner = Aws::S3::Presigner.new(client: @client)
    presigner.presigned_url(:get_object, bucket: BUCKET, key: key, expires_in: expires_in)
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "[ReplayStorage] presigned_url failed for key=#{key}: #{e.class}: #{e.message}"
    raise
  end

  # Convenience singleton — avoids re-building the S3 client on every call.
  def self.client
    @instance ||= new
  end

  private

  def build_client
    Aws::S3::Client.new(
      region: REGION,
      endpoint: ENDPOINT,
      access_key_id: ACCESS_KEY,
      secret_access_key: SECRET_KEY,
      force_path_style: true
    )
  end
end
