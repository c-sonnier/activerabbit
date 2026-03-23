# frozen_string_literal: true

module Uptime
  class DailyRollupJob
    include Sidekiq::Job

    sidekiq_options queue: :default, retry: 2

    def perform
      yesterday = Date.current.yesterday

      ActsAsTenant.without_tenant do
        Uptime::Monitor.find_each do |monitor|
          rollup_for_monitor(monitor, yesterday)
        end
      end
    end

    private

    def rollup_for_monitor(monitor, date)
      checks = Uptime::Check.where(uptime_monitor_id: monitor.id)
                             .where(created_at: date.beginning_of_day.utc..date.end_of_day.utc)

      return if checks.empty?

      response_times = checks.where.not(response_time_ms: nil).pluck(:response_time_ms).sort
      total = checks.count
      successful = checks.where(success: true).count

      p95 = percentile(response_times, 95)
      p99 = percentile(response_times, 99)

      incidents = 0
      prev_success = true
      checks.order(:created_at).pluck(:success).each do |success|
        if !success && prev_success
          incidents += 1
        end
        prev_success = success
      end

      Uptime::DailySummary.upsert(
        {
          uptime_monitor_id: monitor.id,
          account_id: monitor.account_id,
          date: date,
          total_checks: total,
          successful_checks: successful,
          uptime_percentage: total > 0 ? (successful.to_f / total * 100).round(2) : nil,
          avg_response_time_ms: response_times.any? ? (response_times.sum.to_f / response_times.size).round : nil,
          p95_response_time_ms: p95,
          p99_response_time_ms: p99,
          min_response_time_ms: response_times.min,
          max_response_time_ms: response_times.max,
          incidents_count: incidents,
          updated_at: Time.current
        },
        unique_by: [:uptime_monitor_id, :date]
      )
    end

    def percentile(sorted_array, p)
      return nil if sorted_array.empty?
      k = ((p / 100.0) * (sorted_array.size - 1)).ceil
      sorted_array[k]
    end
  end
end
