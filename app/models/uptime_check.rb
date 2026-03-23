# frozen_string_literal: true

class UptimeCheck < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :uptime_monitor

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :recent, -> { order(created_at: :desc) }
end
