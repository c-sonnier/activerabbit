# frozen_string_literal: true

class ReplayIngestJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  LOCAL_STORAGE_DIR = Rails.root.join("storage", "replays")

  def perform(replay_id, raw_events_json)
    replay  = Replay.unscoped.find(replay_id)
    account = replay.account

    ActsAsTenant.with_tenant(account) do
      replay.update!(status: "processing")

      compressed        = Zlib::Deflate.deflate(raw_events_json)
      uncompressed_size = raw_events_json.bytesize
      compressed_size   = compressed.bytesize
      event_count       = JSON.parse(raw_events_json).length
      checksum          = Digest::SHA256.hexdigest(compressed)
      key               = replay.storage_path

      if ReplayStorage::BUCKET.present? || Rails.env.test?
        result = ReplayStorage.client.upload(key: key, data: compressed)
        success = result[:success]
        storage_key = result[:key]
      else
        # Local file storage fallback (dev/demo)
        local_path = LOCAL_STORAGE_DIR.join(key)
        FileUtils.mkdir_p(local_path.dirname)
        File.binwrite(local_path, compressed)
        success = true
        storage_key = "local://#{key}"
      end

      if success
        replay.mark_ready!(
          storage_key:       storage_key,
          compressed_size:   compressed_size,
          uncompressed_size: uncompressed_size,
          event_count:       event_count,
          checksum_sha256:   checksum
        )
        replay.update!(retention_until: 30.days.from_now)
      else
        replay.mark_failed!
      end
    end
  end
end
