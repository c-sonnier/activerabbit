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

    # Check quota before inserting
    unless account.within_quota?(:log_entries)
      Rails.logger.warn "[LogIngest] Quota exceeded for account #{account.id}, dropping #{entries.size} log entries"
      return
    end

    ActsAsTenant.with_tenant(account) do
      symbolized = entries.map { |e| e.deep_symbolize_keys }
      records = LogStore.insert_batch(project, symbolized)

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
