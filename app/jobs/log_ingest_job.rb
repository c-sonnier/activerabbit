# frozen_string_literal: true

class LogIngestJob < ApplicationJob
  queue_as :default

  # Batch-inserts log entries and broadcasts to ActionCable for live tail.
  #
  # @param project_id [Integer]
  # @param entries [Array<Hash>] raw log entry payloads from the API
  def perform(project_id, entries)
    project = Project.find_by(id: project_id)
    return unless project

    account = project.account
    return unless account

    # Check storage quota (1 GB free)
    if account.log_quota_exceeded?
      Rails.logger.warn "[LogIngest] Log storage quota exceeded for account #{account.id}, dropping #{entries.size} log entries"
      return
    end

    ActsAsTenant.with_tenant(account) do
      symbolized = entries.map { |e| e.deep_symbolize_keys }
      records = LogStore.insert_batch(project, symbolized)

      # Track approximate storage bytes used
      batch_bytes = entries.sum { |e| e.to_json.bytesize }
      Account.where(id: account.id).update_all("cached_log_bytes_used = COALESCE(cached_log_bytes_used, 0) + #{batch_bytes.to_i}")

      # Broadcast each entry to ActionCable for live tail
      records.each do |record|
        ts = record[:occurred_at]
        ts = ts.iso8601 if ts.respond_to?(:iso8601)

        ActionCable.server.broadcast(
          "log_stream:#{project.id}",
          {
            id: record[:id],
            level: LogEntry::LEVEL_NAMES[record[:level]]&.to_s,
            message: record[:message],
            source: record[:source],
            trace_id: record[:trace_id],
            occurred_at: ts.to_s
          }
        )
      end

      Rails.logger.info "[LogIngest] Inserted #{records.size} log entries for project #{project.id}"
    end
  rescue => e
    Rails.logger.error "[LogIngest] Failed: #{e.message}"
    raise
  end
end
