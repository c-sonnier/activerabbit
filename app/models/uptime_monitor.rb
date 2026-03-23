# frozen_string_literal: true

class UptimeMonitor < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project, optional: true
  has_many :uptime_checks, dependent: :destroy
  has_many :uptime_daily_summaries, dependent: :destroy

  # TODO: Enable `encrypts :headers` once ActiveRecord::Encryption keys are in credentials
  # encrypts :headers

  STATUSES = %w[up down degraded paused pending].freeze
  HTTP_METHODS = %w[GET HEAD POST].freeze
  INTERVALS = [60, 300, 600].freeze

  validates :name, presence: true
  validates :url, presence: true
  validates :interval_seconds, presence: true, numericality: { greater_than: 0 }
  validates :timeout_seconds, presence: true, numericality: { greater_than: 0 }
  validates :expected_status_code, presence: true, numericality: { greater_than: 0 }
  validates :alert_threshold, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :http_method, inclusion: { in: HTTP_METHODS }
  validate :url_must_be_http

  scope :active, -> { where.not(status: "paused") }
  scope :due_for_check, -> {
    active.where(
      "last_checked_at IS NULL OR last_checked_at <= NOW() - (interval_seconds || ' seconds')::interval"
    )
  }
  scope :by_status, ->(status) { where(status: status) }

  def pause!
    update!(status: "paused")
  end

  def resume!
    update!(status: "pending")
  end

  def paused?
    status == "paused"
  end

  def up?
    status == "up"
  end

  def down?
    status == "down"
  end

  private

  def url_must_be_http
    return if url.blank?
    unless url.match?(%r{\Ahttps?://}i)
      errors.add(:url, "must start with http:// or https://")
    end
  end
end
