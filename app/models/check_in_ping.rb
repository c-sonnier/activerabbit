# frozen_string_literal: true

class CheckInPing < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :check_in

  validates :pinged_at, presence: true
  validates :status, inclusion: { in: %w[success] }

  scope :recent, -> { order(pinged_at: :desc) }
  scope :today, -> { where(pinged_at: Time.current.beginning_of_day..) }
  scope :last_24h, -> { where(pinged_at: 24.hours.ago..) }
  scope :last_7d, -> { where(pinged_at: 7.days.ago..) }
  scope :last_30d, -> { where(pinged_at: 30.days.ago..) }
end
