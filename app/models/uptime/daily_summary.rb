# frozen_string_literal: true

module Uptime
  class DailySummary < ApplicationRecord
    self.table_name = "uptime_daily_summaries"

    acts_as_tenant(:account)

    belongs_to :monitor, class_name: "Uptime::Monitor", foreign_key: :uptime_monitor_id

    scope :for_period, ->(start_date, end_date) { where(date: start_date..end_date) }
    scope :recent, -> { order(date: :desc) }
  end
end
