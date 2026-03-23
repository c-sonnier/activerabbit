# frozen_string_literal: true

class UptimeSchedulerJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  def perform
    ActsAsTenant.without_tenant do
      UptimeMonitor.due_for_check.find_each do |monitor|
        UptimePingJob.perform_async(monitor.id)
      end
    end
  end
end
