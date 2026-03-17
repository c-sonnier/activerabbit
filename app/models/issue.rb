class Issue < ApplicationRecord
  # Multi-tenancy setup - Issue belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project
  has_many :events, dependent: :destroy

  validates :fingerprint, presence: true
  validates_uniqueness_to_tenant :fingerprint, scope: :project_id
  validates :exception_class, presence: true
  validates :top_frame, presence: true
  validates :controller_action, presence: true
  validates :status, inclusion: { in: %w[open wip closed] }
  validates :severity, inclusion: { in: %w[low medium high critical] }, allow_nil: true

  SEVERITIES = %w[low medium high critical].freeze

  # Multi-factor severity scoring weights (total max ~100 points)
  SEVERITY_WEIGHTS = {
    frequency_24h: 25,      # events in last 24h
    total_count: 10,        # lifetime event count
    unique_users: 20,       # unique users affected in 24h
    velocity: 15,           # acceleration: last 1h vs previous 1h
    exception_type: 15,     # inherent severity of the exception class
    recurrence: 10,         # was the issue previously closed and reopened?
    freshness: 5            # first seen recently = higher urgency
  }.freeze

  SEVERITY_SCORE_THRESHOLDS = { critical: 60, high: 35, medium: 15 }.freeze

  CRITICAL_EXCEPTION_CLASSES = %w[
    SecurityError SignalException SystemExit SystemStackError
    NoMemoryError fatal Errno::ENOMEM
    OpenSSL::SSL::SSLError
    PG::ConnectionBad Mysql2::Error::ConnectionError
    Redis::CannotConnectError
  ].freeze

  HIGH_EXCEPTION_CLASSES = %w[
    NoMethodError TypeError NameError ArgumentError
    ActiveRecord::StatementInvalid ActiveRecord::Deadlocked
    ActiveRecord::LockWaitTimeout
    Net::ReadTimeout Net::OpenTimeout Timeout::Error
    Errno::ECONNREFUSED Errno::ECONNRESET
  ].freeze

  MEDIUM_EXCEPTION_CLASSES = %w[
    ActiveRecord::RecordNotFound ActiveRecord::RecordInvalid
    ActiveRecord::RecordNotUnique
    ActionController::RoutingError ActionController::UnknownFormat
    ActionController::InvalidAuthenticityToken
    ActionController::ParameterMissing
    JSON::ParserError Encoding::UndefinedConversionError
  ].freeze

  scope :open, -> { where(status: "open") }
  scope :wip, -> { where(status: "wip") }
  scope :closed, -> { where(status: "closed") }
  scope :recent, -> { order(last_seen_at: :desc) }
  scope :by_frequency, -> { order(count: :desc) }
  scope :by_severity, ->(level) { where(severity: level) }
  scope :critical, -> { where(severity: "critical") }
  scope :high_and_above, -> { where(severity: %w[high critical]) }
  # Fast job-failure filter using the denormalized boolean flag on issues.
  # Falls back to the expensive Event subquery only if the column hasn't been migrated yet.
  scope :from_job_failures, -> {
    if column_names.include?("is_job_failure")
      where(is_job_failure: true)
    else
      where(id: Event.from_job_failures.distinct.select(:issue_id))
    end
  }

  before_save :detect_job_failure
  before_save :calculate_severity!

  def github_pr_url
    read_attribute(:github_pr_url).presence || project&.settings&.dig("issue_pr_urls", id.to_s)
  end

  def self.find_or_create_by_fingerprint(project:, exception_class:, top_frame:, controller_action:, sample_message: nil)
    fingerprint = generate_fingerprint(exception_class, top_frame, controller_action)

    issue = find_by(project: project, fingerprint: fingerprint)
    if issue
      # Atomic SQL increment — prevents lost updates when multiple Sidekiq
      # workers process the same fingerprint concurrently.
      # Ruby-level `count + 1` is a read-then-write race condition.
      Issue.where(id: issue.id).update_all(
        ["count = count + 1, last_seen_at = ?, " \
         "status = CASE WHEN status = 'closed' THEN 'open' ELSE status END, " \
         "closed_at = CASE WHEN status = 'closed' THEN NULL ELSE closed_at END",
         Time.current]
      )
      issue.reload
      return issue
    end

    begin
      create!(
        project: project,
        fingerprint: fingerprint,
        exception_class: exception_class,
        top_frame: top_frame,
        controller_action: controller_action,
        sample_message: sample_message,
        count: 1,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        status: "open"
      )
    rescue ActiveRecord::RecordNotUnique
      # Another worker created the issue between our find_by and create!
      # Find it AND atomically increment (the old code just returned without
      # incrementing — the event was invisible in the count).
      issue = find_by(project: project, fingerprint: fingerprint)
      if issue
        Issue.where(id: issue.id).update_all(
          ["count = count + 1, last_seen_at = ?, " \
           "status = CASE WHEN status = 'closed' THEN 'open' ELSE status END, " \
           "closed_at = CASE WHEN status = 'closed' THEN NULL ELSE closed_at END",
           Time.current]
        )
        issue.reload
      end
      issue
    end
  end

  def mark_wip!
    update!(status: "wip")
  end

  def close!
    update!(status: "closed", closed_at: Time.current)
  end

  def reopen!
    update!(status: "open", closed_at: nil)
  end

  def title
    "#{exception_class} in #{controller_action}"
  end

  def calculated_severity
    score = severity_score
    if score >= SEVERITY_SCORE_THRESHOLDS[:critical]
      "critical"
    elsif score >= SEVERITY_SCORE_THRESHOLDS[:high]
      "high"
    elsif score >= SEVERITY_SCORE_THRESHOLDS[:medium]
      "medium"
    else
      "low"
    end
  end

  # Detailed breakdown of all severity factors (useful for UI tooltips / debugging)
  def severity_score_breakdown
    {
      frequency_24h: frequency_24h_score,
      total_count: total_count_score,
      unique_users: unique_users_score,
      velocity: velocity_score,
      exception_type: exception_type_score,
      recurrence: recurrence_score,
      freshness: freshness_score,
      total: severity_score
    }
  end

  def severity_score
    frequency_24h_score +
      total_count_score +
      unique_users_score +
      velocity_score +
      exception_type_score +
      recurrence_score +
      freshness_score
  end

  def update_severity!
    new_severity = calculated_severity
    update_column(:severity, new_severity) if severity != new_severity
    new_severity
  end

  # Severity badge helpers for UI
  def severity_color
    case severity
    when "critical" then "red"
    when "high" then "orange"
    when "medium" then "yellow"
    else "gray"
    end
  end

  def severity_icon
    case severity
    when "critical" then "🔴"
    when "high" then "🟠"
    when "medium" then "🟡"
    else "⚪"
    end
  end

  def source_location
    "#{controller_action} (#{top_frame})"
  end

  def events_last_24h
    events.where("occurred_at > ?", 24.hours.ago).count
  end

  # Unique users affected (last 24h)
  def unique_users_affected_24h
    events.where("occurred_at > ?", 24.hours.ago)
          .where.not(user_id_hash: nil)
          .distinct
          .count(:user_id_hash)
  end

  # Most common environment
  def primary_environment
    events.where.not(environment: nil)
          .group(:environment)
          .order("count_id DESC")
          .limit(1)
          .count(:id)
          .keys
          .first || "production"
  end

  # Most recent release version
  def current_release
    events.where.not(release_version: nil)
          .order(occurred_at: :desc)
          .limit(1)
          .pluck(:release_version)
          .first || "unknown"
  end

  # Impact percentage (errors in last 24h / total requests in last 24h)
  # Note: This requires tracking total requests, which we'll estimate from all events
  def impact_percentage_24h
    return 0.0 if project.nil?

    error_count = events_last_24h
    return 0.0 if error_count.zero?

    # Get total events for the project in last 24h as a proxy for total requests
    total_events = ActsAsTenant.without_tenant do
      Event.where(project_id: project.id)
           .where("occurred_at > ?", 24.hours.ago)
           .count
    end

    return 0.0 if total_events.zero?

    ((error_count.to_f / total_events.to_f) * 100).round(2)
  end

  # Construct full URL from most recent event
  def full_url
    recent_event = events.order(occurred_at: :desc).first
    return nil unless recent_event

    # Get data from event or context
    ctx = recent_event.context || {}
    req = (ctx["request"] || ctx[:request] || {})

    host = recent_event.server_name || req["server_name"] || req[:server_name]
    port = req["server_port"] || req[:server_port]
    path = recent_event.request_path || req["request_path"] || req[:request_path]

    return nil if host.blank? || path.blank?

    # Determine scheme (https if port 443, otherwise http)
    scheme = (port.to_s == "443") ? "https" : "http"

    # Build URL
    url = "#{scheme}://#{host}"
    url += ":#{port}" if port.present? && !["80", "443"].include?(port.to_s)
    url += path
    url
  end

  def self.ransackable_attributes(auth_object = nil)
    ["account_id", "ai_summary", "ai_summary_generated_at", "closed_at",
    "controller_action", "count", "created_at", "exception_class",
    "fingerprint", "first_seen_at", "id", "id_value", "last_seen_at",
    "project_id", "sample_message", "severity", "status", "top_frame", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account", "events", "project"]
  end

  private

  # Auto-detect whether this issue comes from a background job.
  # Workers / job classes don't follow the "SomeController#action" pattern.
  def detect_job_failure
    return unless respond_to?(:is_job_failure) && has_attribute?(:is_job_failure)
    return unless controller_action_changed? || new_record?

    self.is_job_failure = controller_action.present? && !controller_action.include?("Controller#")
  end

  def calculate_severity!
    return unless has_attribute?(:severity)
    return unless count_changed? || new_record? || severity.nil?

    self.severity = calculated_severity
  end

  # --- Severity scoring factors ---

  def frequency_24h_score
    c = events_last_24h
    max = SEVERITY_WEIGHTS[:frequency_24h]
    if c >= 200 then max
    elsif c >= 50 then (max * 0.8).round
    elsif c >= 20 then (max * 0.6).round
    elsif c >= 5  then (max * 0.3).round
    elsif c >= 1  then (max * 0.1).round
    else 0
    end
  end

  def total_count_score
    max = SEVERITY_WEIGHTS[:total_count]
    if count >= 5000 then max
    elsif count >= 1000 then (max * 0.8).round
    elsif count >= 100  then (max * 0.5).round
    elsif count >= 10   then (max * 0.2).round
    else 0
    end
  end

  def unique_users_score
    users = unique_users_affected_24h
    max = SEVERITY_WEIGHTS[:unique_users]
    if users >= 50  then max
    elsif users >= 20 then (max * 0.8).round
    elsif users >= 5  then (max * 0.5).round
    elsif users >= 2  then (max * 0.25).round
    else 0
    end
  end

  # Compare event rate in the last hour vs the hour before to detect spikes.
  def velocity_score
    now = Time.current
    last_hour   = events.where(occurred_at: (now - 1.hour)..now).count
    prev_hour   = events.where(occurred_at: (now - 2.hours)..(now - 1.hour)).count
    max = SEVERITY_WEIGHTS[:velocity]

    return 0 if last_hour == 0

    if prev_hour == 0
      last_hour >= 5 ? max : (max * 0.5).round
    else
      ratio = last_hour.to_f / prev_hour
      if ratio >= 5.0    then max
      elsif ratio >= 3.0 then (max * 0.7).round
      elsif ratio >= 2.0 then (max * 0.4).round
      else 0
      end
    end
  end

  def exception_type_score
    max = SEVERITY_WEIGHTS[:exception_type]
    klass = exception_class.to_s

    if CRITICAL_EXCEPTION_CLASSES.any? { |c| klass.include?(c) }
      max
    elsif HIGH_EXCEPTION_CLASSES.any? { |c| klass.include?(c) }
      (max * 0.6).round
    elsif MEDIUM_EXCEPTION_CLASSES.any? { |c| klass.include?(c) }
      (max * 0.3).round
    else
      0
    end
  end

  # Previously-resolved issues that reappear are more urgent.
  def recurrence_score
    max = SEVERITY_WEIGHTS[:recurrence]
    if closed_at.present? && status != "closed"
      max
    elsif count_changed? && count > 1 && status == "open" && closed_at_was.present?
      (max * 0.5).round
    else
      0
    end
  end

  # Brand-new errors deserve more attention.
  def freshness_score
    max = SEVERITY_WEIGHTS[:freshness]
    age = Time.current - (first_seen_at || created_at || Time.current)
    if age < 1.hour   then max
    elsif age < 6.hours then (max * 0.6).round
    elsif age < 1.day   then (max * 0.3).round
    else 0
    end
  end

  # Exception classes that should be grouped by originating code location
  # These are common errors where the controller action is just the entry point,
  # but the real bug lives in shared code (base controllers, concerns, etc.)
  ORIGIN_BASED_FINGERPRINT_EXCEPTIONS = %w[
    ActiveRecord::RecordNotFound
    ActionController::RoutingError
    ActionController::UnknownFormat
    ActionController::InvalidAuthenticityToken
    ActionController::ParameterMissing
  ].freeze

  def self.generate_fingerprint(exception_class, top_frame, controller_action)
    # Normalize top frame (remove line numbers, normalize paths)
    normalized_frame = top_frame.gsub(/:\d+/, ":N").gsub(/\/\d+\//, "/N/")

    # For common exceptions, group by exception_class + originating code location (top_frame)
    # This groups errors that come from the same code path, regardless of entry point
    # Example: RecordNotFound from base_controller.rb#authenticate_with_bearer_token
    #          called via HoursController#index, TasksController#index, etc.
    #          → ALL grouped into 1 issue (same root cause, single fix needed)
    if ORIGIN_BASED_FINGERPRINT_EXCEPTIONS.include?(exception_class)
      components = [
        exception_class,
        normalized_frame # Group by originating code location, not entry point
      ].compact
    else
      # Standard fingerprinting for other errors
      components = [
        exception_class,
        normalized_frame,
        controller_action
      ].compact
    end

    Digest::SHA256.hexdigest(components.join("|"))
  end
end
