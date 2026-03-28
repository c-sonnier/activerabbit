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
end
