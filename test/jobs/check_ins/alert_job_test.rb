# frozen_string_literal: true

require "test_helper"

module CheckIns
  class AlertJobTest < ActiveSupport::TestCase
    test "uses alerts queue" do
      assert_equal :alerts, AlertJob.sidekiq_options_hash["queue"]
    end

    test "perform returns early when check_in missing" do
      assert_nothing_raised { AlertJob.new.perform(0) }
    end
  end
end
