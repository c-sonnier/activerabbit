# frozen_string_literal: true

module Uptime
  class Check < ApplicationRecord
    self.table_name = "uptime_checks"

    acts_as_tenant(:account)

    belongs_to :monitor, class_name: "Uptime::Monitor", foreign_key: :uptime_monitor_id

    scope :successful, -> { where(success: true) }
    scope :failed, -> { where(success: false) }
    scope :recent, -> { order(created_at: :desc) }
  end
end
