# frozen_string_literal: true

class LogArchiveJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 10_000

  # Archives expired log entries to R2 cold storage, then deletes them.
  # Runs daily via Sidekiq Cron.
  def perform
    ActsAsTenant.without_tenant do
      Account.find_each do |account|
        archive_for_account(account)
      rescue => e
        Rails.logger.error "[LogArchive] Error archiving account #{account.id}: #{e.message}"
      end
    end
  end

  private

  def archive_for_account(account)
    cutoff = account.data_retention_cutoff
    expired_count = LogEntry.where(account_id: account.id)
                            .where("occurred_at < ?", cutoff)
                            .count

    return if expired_count.zero?

    Rails.logger.info "[LogArchive] Archiving #{expired_count} log entries for account #{account.id} (cutoff: #{cutoff})"

    account.projects.find_each do |project|
      ndjson = LogStore.archive_before(project, cutoff)
      next unless ndjson

      # Upload to R2 if configured
      upload_to_r2(account, project, cutoff, ndjson) if r2_configured?
    end

    # Delete archived entries in batches
    total_deleted = 0
    loop do
      deleted = LogEntry.where(account_id: account.id)
                        .where("occurred_at < ?", cutoff)
                        .limit(BATCH_SIZE)
                        .delete_all

      total_deleted += deleted
      break if deleted == 0
      sleep(0.1) if deleted == BATCH_SIZE
    end

    Rails.logger.info "[LogArchive] Deleted #{total_deleted} archived log entries for account #{account.id}"
  end

  def r2_configured?
    ENV["R2_ACCESS_KEY_ID"].present? && ENV["R2_BUCKET"].present?
  end

  def upload_to_r2(account, project, cutoff, ndjson)
    key = "logs/#{account.id}/#{project.id}/#{cutoff.strftime('%Y-%m-%d')}.ndjson.gz"

    compressed = ActiveSupport::Gzip.compress(ndjson)

    r2_client.put_object(
      bucket: ENV["R2_BUCKET"],
      key: key,
      body: compressed,
      content_encoding: "gzip",
      content_type: "application/x-ndjson"
    )

    Rails.logger.info "[LogArchive] Uploaded #{key} (#{compressed.bytesize} bytes)"
  rescue => e
    Rails.logger.error "[LogArchive] R2 upload failed for #{key}: #{e.message}"
  end

  def r2_client
    @r2_client ||= Aws::S3::Client.new(
      access_key_id: ENV["R2_ACCESS_KEY_ID"],
      secret_access_key: ENV["R2_SECRET_ACCESS_KEY"],
      endpoint: ENV["R2_ENDPOINT"],
      region: "auto"
    )
  end
end
