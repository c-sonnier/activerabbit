class LogStore
  class << self
    def insert_batch(project, entries)
      now = Time.current
      records = entries.map do |entry|
        {
          account_id: project.account_id,
          project_id: project.id,
          level: normalize_level(entry[:level]),
          message: entry[:message],
          message_template: entry[:message_template],
          params: LogEntry.scrub_pii(entry[:params] || {}),
          context: LogEntry.scrub_pii(entry[:context] || {}),
          trace_id: entry[:trace_id],
          span_id: entry[:span_id],
          request_id: entry[:request_id],
          issue_id: resolve_issue_id(entry[:trace_id], entry[:request_id]),
          environment: entry[:environment] || "production",
          release: entry[:release],
          source: entry[:source],
          occurred_at: entry[:occurred_at] || now,
          created_at: now,
          updated_at: now
        }
      end

      LogEntry.insert_all(records) if records.any?
      records
    end

    def search(project, filters, time_range, limit: 100, cursor: nil)
      scope = LogEntry.where(project: project)
                      .where("occurred_at > ?", time_range.ago)
                      .reverse_chronological
                      .limit(limit)

      scope = scope.by_level(filters[:level]) if filters[:level]
      scope = scope.where(environment: filters[:environment]) if filters[:environment]
      scope = scope.where(source: filters[:source]) if filters[:source]
      scope = scope.where("message ILIKE ?", "%#{sanitize_like(filters[:message])}%") if filters[:message]
      scope = scope.where(trace_id: filters[:trace_id]) if filters[:trace_id]
      scope = scope.where(request_id: filters[:request_id]) if filters[:request_id]

      if filters[:params]
        filters[:params].each do |key, value|
          scope = scope.where("params @> ?", { key => value }.to_json)
        end
      end

      if cursor
        scope = scope.where("(occurred_at, id) < (?, ?)", cursor[:occurred_at], cursor[:id])
      end

      scope
    end

    def find_by_trace(trace_id)
      LogEntry.for_trace(trace_id).chronological
    end

    def find_by_issue(issue_id, time_range: 24.hours)
      LogEntry.for_issue(issue_id)
              .where("occurred_at > ?", time_range.ago)
              .chronological
    end

    def archive_before(project, cutoff)
      entries = LogEntry.where(project: project)
                        .where("occurred_at < ?", cutoff)
                        .order(:occurred_at)

      return nil unless entries.exists?

      entries.find_each.map { |e|
        {
          id: e.id, level: e.level_name, message: e.message,
          message_template: e.message_template, params: e.params,
          context: e.context, trace_id: e.trace_id, span_id: e.span_id,
          request_id: e.request_id, issue_id: e.issue_id,
          environment: e.environment, release: e.release,
          source: e.source, occurred_at: e.occurred_at.iso8601(6)
        }.to_json
      }.join("\n")
    end

    private

    def normalize_level(level)
      return level if level.is_a?(Integer)
      LogEntry::LEVELS[level.to_sym] || 2
    end

    def resolve_issue_id(trace_id, request_id)
      return nil unless trace_id || request_id

      event = if trace_id
        Event.where(trace_id: trace_id).order(occurred_at: :desc).first
      elsif request_id
        Event.where(request_id: request_id).order(occurred_at: :desc).first
      end

      event&.issue_id
    end

    def sanitize_like(str)
      str.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
