# frozen_string_literal: true

module Uptime
  class SchedulerJob
    include Sidekiq::Job

    sidekiq_options queue: :default, retry: 0

    def perform
      ActsAsTenant.without_tenant do
        Uptime::Monitor.due_for_check.find_each do |monitor|
          Uptime::PingJob.perform_async(monitor.id)
        end
      end
    end
  end
end
