# frozen_string_literal: true

module Uptime
  class SslExpiryCheckJob
    include Sidekiq::Job

    sidekiq_options queue: :default, retry: 1

    WARN_DAYS = [30, 14, 7].freeze

    def perform
      ActsAsTenant.without_tenant do
        Uptime::Monitor.active.where.not(ssl_expiry: nil).find_each do |monitor|
          days_until_expiry = (monitor.ssl_expiry.to_date - Date.current).to_i

          WARN_DAYS.each do |warn_at|
            next unless days_until_expiry <= warn_at

            lock_key = "ssl_alert:#{monitor.id}:#{warn_at}"
            lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: 24.hours.to_i, nx: true) }
            next unless lock_acquired

            Uptime::AlertJob.perform_async(
              monitor.id,
              "ssl_expiry",
              { "days_until_expiry" => days_until_expiry, "ssl_expiry" => monitor.ssl_expiry.iso8601 }
            )
            break
          end
        end
      end
    end
  end
end
