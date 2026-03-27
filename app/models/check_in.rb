# frozen_string_literal: true

class CheckIn < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project
  has_many :pings, class_name: "CheckInPing", dependent: :destroy

  KINDS = %w[cron heartbeat].freeze
  STATUSES = %w[success missed reporting].freeze

  validates :identifier, presence: true
  validates_uniqueness_to_tenant :identifier, scope: :project_id
  validates :kind, inclusion: { in: KINDS }
  validates :last_status, inclusion: { in: STATUSES }, allow_nil: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :by_status, ->(status) { where(last_status: status) }
  scope :overdue, -> {
    enabled
      .where.not(last_seen_at: nil)
      .where("last_seen_at < NOW() - (heartbeat_interval_seconds || ' seconds')::interval")
  }
  scope :never_seen, -> {
    enabled.where(last_seen_at: nil)
  }

  before_validation :generate_token, on: :create

  def ping!
    update!(
      last_seen_at: Time.current,
      last_status: "reporting"
    )
  end

  def token
    read_attribute(:identifier)
  end

  def overdue?
    return false unless enabled? && last_seen_at.present? && heartbeat_interval_seconds.present?

    last_seen_at < heartbeat_interval_seconds.seconds.ago
  end

  def status_display
    return "new" if last_seen_at.nil?
    return "missed" if overdue?

    "healthy"
  end

  def status_color
    case status_display
    when "healthy" then "green"
    when "missed" then "red"
    when "new" then "gray"
    else "gray"
    end
  end

  def interval_display
    return "—" unless heartbeat_interval_seconds.present?

    case heartbeat_interval_seconds
    when 0..59 then "#{heartbeat_interval_seconds}s"
    when 60..3599 then "#{(heartbeat_interval_seconds / 60.0).round}m"
    when 3600..86399 then "#{(heartbeat_interval_seconds / 3600.0).round}h"
    else "#{(heartbeat_interval_seconds / 86400.0).round}d"
    end
  end

  def ping_url
    host = ENV.fetch("APP_HOST", "http://localhost:3000")
    host = "https://#{host}" unless host.start_with?("http://", "https://")
    "#{host}/api/v1/check_in/#{token}"
  end

  def should_alert?
    return false unless enabled?
    return false unless overdue?
    return false if last_alerted_at.present? && last_alerted_at > 1.hour.ago

    true
  end

  def mark_alerted!
    update!(last_alerted_at: Time.current, last_status: "missed")
  end

  private

  def generate_token
    self.identifier ||= SecureRandom.hex(10)
  end
end
