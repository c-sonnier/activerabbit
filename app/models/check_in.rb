# frozen_string_literal: true

class CheckIn < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project
  has_many :pings, class_name: "CheckInPing", dependent: :destroy

  KINDS = %w[cron heartbeat].freeze
  STATUSES = %w[success missed reporting].freeze

  SLUG_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/.freeze

  validates :identifier, presence: true
  validates_uniqueness_to_tenant :identifier, scope: :project_id
  validates :description, presence: true
  validates :slug, format: { with: SLUG_FORMAT, message: "only lowercase letters, numbers, hyphens, underscores" }, allow_blank: true
  validates :slug, uniqueness: { scope: :project_id }, allow_blank: true
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
  before_validation :normalize_slug
  before_validation :ensure_slug_from_description
  before_validation :force_utc_timezone

  def ping!
    update!(
      last_seen_at: Time.current,
      last_status: "reporting"
    )
  end

  # Records a successful heartbeat (updates last_seen_at + CheckInPing). Caller must run inside ActsAsTenant.with_tenant(account).
  def record_success_ping!(source_ip: nil)
    ping!
    pings.create!(
      status: "success",
      source_ip: source_ip,
      pinged_at: last_seen_at
    )
  end

  # Failed run from the app (after :in_progress). Does not move last_seen_at / success clock.
  def record_error_ping!(source_ip: nil)
    update!(
      run_started_at: nil,
      last_status: "missed"
    )
    pings.create!(
      status: "error",
      source_ip: source_ip,
      pinged_at: Time.current
    )
  end

  def token
    read_attribute(:identifier)
  end

  def overdue?
    return false unless enabled? && heartbeat_interval_seconds.present?

    if run_started_at.present? && run_started_at < heartbeat_interval_seconds.seconds.ago
      return true
    end

    return false unless last_seen_at.present?

    last_seen_at < heartbeat_interval_seconds.seconds.ago
  end

  # Latest row wins: error after success shows "error" until the next successful :ok/:success ping.
  def status_display
    if run_started_at.present?
      return "missed" if heartbeat_interval_seconds.present? && run_started_at < heartbeat_interval_seconds.seconds.ago

      return "running"
    end

    latest = pings.order(pinged_at: :desc, id: :desc).first
    return "error" if latest&.status == "error"

    return "new" if last_seen_at.nil?
    return "missed" if overdue?

    "healthy"
  end

  def status_color
    case status_display
    when "healthy" then "green"
    when "missed" then "red"
    when "error" then "red"
    when "running" then "blue"
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

    latest = pings.order(pinged_at: :desc, id: :desc).first
    if latest&.status == "error"
      return false if last_alerted_at.present? && last_alerted_at >= latest.pinged_at
      return true
    end

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

  # One user-facing name (description) → stable monitor id for the SDK (slug) when missing.
  def ensure_slug_from_description
    return if slug.present?
    return if description.to_s.strip.blank?

    base = description.to_s.strip.parameterize(separator: "_")
    base = "monitor_#{SecureRandom.hex(4)}" if base.blank? || base !~ SLUG_FORMAT

    candidate = base
    n = 0
    while slug_taken?(candidate)
      n += 1
      candidate = "#{base}_#{n}"
    end

    self.slug = candidate
  end

  def slug_taken?(candidate)
    rel = self.class.where(project_id: project_id, slug: candidate)
    rel = rel.where.not(id: id) if persisted?
    rel.exists?
  end

  def normalize_slug
    raw = slug.to_s.strip
    self.slug = raw.blank? ? nil : raw.parameterize(separator: "_")
  end

  def force_utc_timezone
    self.timezone = "UTC"
  end
end
