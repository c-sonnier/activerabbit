# frozen_string_literal: true

require "test_helper"

module CheckIns
  class MonitorJobTest < ActiveSupport::TestCase
    setup do
      CheckIns::AlertJob.jobs.clear
    end

    test "uses priority queue" do
      assert_equal :priority, MonitorJob.sidekiq_options_hash["queue"]
    end

    test "enqueues AlertJob for overdue check-ins and marks alerted" do
      overdue = check_ins(:overdue_alert)
      refute overdue.reload.last_alerted_at&.> 1.minute.ago

      MonitorJob.new.perform

      assert_equal 1, AlertJob.jobs.size
      assert_equal overdue.id, AlertJob.jobs.first["args"].first

      overdue.reload
      assert overdue.last_alerted_at.present?
      assert_equal "missed", overdue.last_status
    end

    test "does not enqueue for healthy check-ins" do
      CheckIns::AlertJob.jobs.clear
      MonitorJob.new.perform
      job_args = AlertJob.jobs.map { |j| j["args"].first }
      refute_includes job_args, check_ins(:healthy).id
    end
  end
end
