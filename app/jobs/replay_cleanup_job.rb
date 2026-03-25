# frozen_string_literal: true

class ReplayCleanupJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform
    cleaned = 0

    ActsAsTenant.without_tenant do
      Replay.expired.where(status: "ready").find_each(batch_size: 100) do |replay|
        if replay.storage_key.present?
          ReplayStorage.client.delete(key: replay.storage_key)
        end

        replay.update!(status: "expired")
        cleaned += 1
      end
    end

    Rails.logger.info "[ReplayCleanupJob] Cleaned up #{cleaned} expired replay(s)"
  end
end
