class LogEntry < ApplicationRecord
  acts_as_tenant :account

  belongs_to :project
  belongs_to :issue, optional: true

  LEVELS = { trace: 0, debug: 1, info: 2, warn: 3, error: 4, fatal: 5 }.freeze
  LEVEL_NAMES = LEVELS.invert.freeze

  validates :message, presence: true
  validates :level, presence: true, inclusion: { in: LEVELS.values }
  validates :occurred_at, presence: true

  scope :by_level, ->(level) { where(level: LEVELS[level.to_sym]) }
  scope :recent, ->(duration = 1.hour) { where("occurred_at > ?", duration.ago) }
  scope :for_trace, ->(trace_id) { where(trace_id: trace_id) }
  scope :for_issue, ->(issue_id) { where(issue_id: issue_id) }
  scope :for_request, ->(request_id) { where(request_id: request_id) }
  scope :chronological, -> { order(occurred_at: :asc) }
  scope :reverse_chronological, -> { order(occurred_at: :desc) }

  def level_name
    LEVEL_NAMES[level]&.to_s
  end

  def self.scrub_pii(data)
    return data unless data.is_a?(Hash)
    scrubbed = data.deep_dup
    pii_fields = %w[email password token secret key ssn phone credit_card]

    scrubbed.each do |key, value|
      if pii_fields.any? { |field| key.to_s.match?(/#{Regexp.escape(field)}/i) }
        scrubbed[key] = "[SCRUBBED]"
      elsif value.is_a?(Hash)
        scrubbed[key] = scrub_pii(value)
      end
    end
    scrubbed
  end
end
