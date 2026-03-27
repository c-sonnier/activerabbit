# frozen_string_literal: true

module CheckIns
  class MonitorJob
    include Sidekiq::Job

    sidekiq_options queue: :default, retry: 0

    def perform
      ActsAsTenant.without_tenant do
        ::CheckIn.enabled.find_each do |check_in|
          next unless check_in.should_alert?

          CheckIns::AlertJob.perform_async(check_in.id)
          check_in.mark_alerted!
        end
      end
    end
  end
end
