# frozen_string_literal: true

class UptimeDailySummary < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :uptime_monitor

  scope :for_period, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recent, -> { order(date: :desc) }
end
