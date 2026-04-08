class Replay < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :account
  belongs_to :project
  belongs_to :issue, optional: true

  STATUSES = %w[pending processing ready failed expired].freeze

  validates :replay_id, presence: true
  validates :session_id, presence: true
  validates :started_at, presence: true
  validates :duration_ms, presence: true,
                          numericality: { greater_than: 0 }
  validates :event_count, numericality: { greater_than: 0 }, allow_nil: true
  validates :compressed_size, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :uncompressed_size, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  scope :ready, -> { where(status: "ready") }
  scope :by_project, ->(project_id) { where(project_id: project_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :expired, -> { where("retention_until < ?", Time.current) }
  scope :with_issue, -> { where.not(issue_id: nil) }

  def expired?
    retention_until.present? && retention_until < Time.current
  end

  def storage_path
    "replays/#{account_id}/#{project_id}/#{replay_id}"
  end

  def mark_ready!(storage_key:, compressed_size:, uncompressed_size:, event_count:, checksum_sha256:)
    update!(
      storage_key: storage_key,
      compressed_size: compressed_size,
      uncompressed_size: uncompressed_size,
      event_count: event_count,
      checksum_sha256: checksum_sha256,
      status: "ready",
      uploaded_at: Time.current
    )
  end

  def mark_failed!
    update!(status: "failed")
  end

  # URL shown in the UI. Recordings store the browser's location.href, which in
  # dev is often http://localhost:... — replace that origin with the project's
  # configured app URL so /acme-web/replays lists the real app domain, not the dashboard host.
  def display_url_for_project(project)
    return url if url.blank?
    return url unless project&.url.present?

    begin
      recorded = URI.parse(url)
      app = URI.parse(project.url)
      return url unless self.class.development_host?(recorded.host)
      return url if recorded.host&.downcase == app.host&.downcase

      port = app.port
      default_port = (app.scheme == "https" ? 443 : 80)
      port_suffix = port && port != default_port ? ":#{port}" : ""

      path = recorded.path.presence || "/"
      qs = recorded.query.present? ? "?#{recorded.query}" : ""
      frag = recorded.fragment.present? ? "##{recorded.fragment}" : ""
      "#{app.scheme}://#{app.host}#{port_suffix}#{path}#{qs}#{frag}"
    rescue URI::InvalidURIError, ArgumentError
      url
    end
  end

  def display_url_differs_from_recorded?(project)
    url.present? && display_url_for_project(project) != url
  end

  def self.development_host?(host)
    return true if host.blank?

    h = host.downcase.delete("[]") # [::1] -> ::1
    return true if %w[localhost 127.0.0.1 0.0.0.0 ::1].include?(h)
    return true if h.end_with?(".lvh.me") || h == "lvh.me"

    false
  end

  # True when the session was recorded on this ActiveRabbit deployment (same host as APP_HOST).
  # Those are almost always mistakes: snippet pasted in the dashboard instead of the customer's site.
  def recorded_on_app_host?
    self.class.recorded_on_app_host?(url)
  end

  def self.recorded_on_app_host?(url_string)
    app_host = normalize_host_for_compare(ENV["APP_HOST"].to_s)
    return false if app_host.blank?

    begin
      recorded = normalize_host_for_compare(URI.parse(url_string.to_s).host)
      return false if recorded.blank?

      recorded == app_host
    rescue URI::InvalidURIError, ArgumentError
      false
    end
  end

  def self.normalize_host_for_compare(host)
    return nil if host.blank?

    host.to_s.downcase.sub(/\Awww\./, "").presence
  end
end
