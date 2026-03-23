# Uptime Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add server-side uptime/heartbeat monitoring where clients add URLs, ActiveRabbit pings them, collects metrics, and alerts on downtime.

**Architecture:** Sidekiq-cron schedules ping jobs every minute. Each ping uses Net::HTTP with detailed timing. Results stored in PostgreSQL with daily rollups. Alerts via existing Slack/Discord/email services. UI built with Hotwire/Tailwind matching existing admin patterns.

**Tech Stack:** Rails 8, PostgreSQL, Sidekiq + sidekiq-cron, Net::HTTP, Tailwind CSS, Hotwire/Stimulus, Redis (for locks)

**Spec:** `docs/superpowers/specs/2026-03-22-uptime-monitoring-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `db/migrate/XXXX_create_uptime_monitors.rb` | Schema for monitors |
| `db/migrate/XXXX_create_uptime_checks.rb` | Schema for check results |
| `db/migrate/XXXX_create_uptime_daily_summaries.rb` | Schema for rollups |
| `app/models/uptime_monitor.rb` | Monitor model with validations, scopes, status logic |
| `app/models/uptime_check.rb` | Check result model |
| `app/models/uptime_daily_summary.rb` | Daily aggregate model |
| `app/jobs/uptime_scheduler_job.rb` | Cron job — finds due monitors, enqueues pings |
| `app/jobs/uptime_ping_job.rb` | Worker — performs HTTP check, saves result, triggers alerts |
| `app/jobs/uptime_alert_job.rb` | Worker — sends down/up/SSL alerts via Slack/Discord/email |
| `app/jobs/uptime_daily_rollup_job.rb` | Cron job — aggregates daily summaries |
| `app/jobs/uptime_ssl_expiry_check_job.rb` | Cron job — daily SSL cert expiry warnings |
| `app/controllers/uptime_controller.rb` | Dashboard, CRUD, pause/resume/check_now |
| `app/policies/uptime_monitor_policy.rb` | Pundit policy — owner/admin full, member read-only |
| `app/views/uptime/index.html.erb` | Dashboard with summary cards + monitors table |
| `app/views/uptime/show.html.erb` | Monitor detail with charts + checks table |
| `app/views/uptime/new.html.erb` | New monitor form wrapper |
| `app/views/uptime/edit.html.erb` | Edit monitor form wrapper |
| `app/views/uptime/_form.html.erb` | Shared form partial |
| `app/views/uptime/_monitor_row.html.erb` | Table row partial for Turbo updates |
| `app/javascript/controllers/uptime_chart_controller.js` | Stimulus — response time chart |
| `spec/models/uptime_monitor_spec.rb` | Model tests |
| `spec/models/uptime_check_spec.rb` | Model tests |
| `spec/jobs/uptime_scheduler_job_spec.rb` | Scheduler tests |
| `spec/jobs/uptime_ping_job_spec.rb` | Ping job tests |
| `spec/jobs/uptime_alert_job_spec.rb` | Alert job tests |
| `spec/requests/uptime_spec.rb` | Controller/integration tests |

### Modified Files
| File | Change |
|------|--------|
| `config/routes.rb` | Add uptime routes (top-level + project-scoped + slug-scoped) |
| `config/initializers/sidekiq_cron.rb` | Add 3 cron entries |
| `app/views/layouts/admin.html.erb` | Add Uptime nav item in sidebar |
| `app/jobs/data_retention_job.rb` | Add uptime_checks cleanup |
| `app/services/slack_notification_service.rb` | Add uptime alert message builder |
| `app/services/discord_notification_service.rb` | Add uptime alert message builder |

---

## Task 1: Database Migrations

**Files:**
- Create: `db/migrate/XXXX_create_uptime_monitors.rb`
- Create: `db/migrate/XXXX_create_uptime_checks.rb`
- Create: `db/migrate/XXXX_create_uptime_daily_summaries.rb`

- [ ] **Step 1: Generate uptime_monitors migration**

```bash
cd /Users/alex/GPT/activeagent/activerabbit
rails generate migration CreateUptimeMonitors
```

Edit the generated migration:

```ruby
# frozen_string_literal: true

class CreateUptimeMonitors < ActiveRecord::Migration[8.0]
  def change
    create_table :uptime_monitors do |t|
      t.bigint :account_id, null: false
      t.bigint :project_id
      t.string :name, null: false
      t.string :url, null: false
      t.string :http_method, default: "GET", null: false
      t.integer :expected_status_code, default: 200, null: false
      t.integer :interval_seconds, default: 300, null: false
      t.integer :timeout_seconds, default: 30, null: false
      t.jsonb :headers, default: {}
      t.text :body
      t.string :region, default: "us-east"
      t.string :status, default: "pending", null: false
      t.datetime :last_checked_at
      t.integer :last_status_code
      t.integer :last_response_time_ms
      t.integer :consecutive_failures, default: 0, null: false
      t.integer :alert_threshold, default: 3, null: false
      t.datetime :ssl_expiry
      t.timestamps
    end

    add_foreign_key :uptime_monitors, :accounts
    add_foreign_key :uptime_monitors, :projects
    add_index :uptime_monitors, :account_id
    add_index :uptime_monitors, :project_id
    add_index :uptime_monitors, [:status, :last_checked_at]
  end
end
```

- [ ] **Step 2: Generate uptime_checks migration**

```bash
rails generate migration CreateUptimeChecks
```

Edit:

```ruby
# frozen_string_literal: true

class CreateUptimeChecks < ActiveRecord::Migration[8.0]
  def change
    create_table :uptime_checks do |t|
      t.bigint :uptime_monitor_id, null: false
      t.bigint :account_id, null: false
      t.integer :status_code
      t.integer :response_time_ms
      t.boolean :success, null: false, default: false
      t.text :error_message
      t.string :region, default: "us-east"
      t.integer :dns_time_ms
      t.integer :connect_time_ms
      t.integer :tls_time_ms
      t.integer :ttfb_ms
      t.datetime :created_at, null: false
    end

    add_foreign_key :uptime_checks, :uptime_monitors
    add_foreign_key :uptime_checks, :accounts
    add_index :uptime_checks, [:uptime_monitor_id, :created_at]
    add_index :uptime_checks, [:account_id, :created_at]
  end
end
```

- [ ] **Step 3: Generate uptime_daily_summaries migration**

```bash
rails generate migration CreateUptimeDailySummaries
```

Edit:

```ruby
# frozen_string_literal: true

class CreateUptimeDailySummaries < ActiveRecord::Migration[8.0]
  def change
    create_table :uptime_daily_summaries do |t|
      t.bigint :uptime_monitor_id, null: false
      t.bigint :account_id, null: false
      t.date :date, null: false
      t.integer :total_checks, default: 0, null: false
      t.integer :successful_checks, default: 0, null: false
      t.decimal :uptime_percentage, precision: 5, scale: 2
      t.integer :avg_response_time_ms
      t.integer :p95_response_time_ms
      t.integer :p99_response_time_ms
      t.integer :min_response_time_ms
      t.integer :max_response_time_ms
      t.integer :incidents_count, default: 0, null: false
      t.timestamps
    end

    add_foreign_key :uptime_daily_summaries, :uptime_monitors
    add_foreign_key :uptime_daily_summaries, :accounts
    add_index :uptime_daily_summaries, [:uptime_monitor_id, :date], unique: true
    add_index :uptime_daily_summaries, [:account_id, :date]
  end
end
```

- [ ] **Step 4: Run migrations**

```bash
rails db:migrate
```

Expected: 3 tables created, schema.rb updated.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_create_uptime_monitors.rb db/migrate/*_create_uptime_checks.rb db/migrate/*_create_uptime_daily_summaries.rb db/schema.rb
git commit -m "feat(uptime): add database migrations for uptime_monitors, uptime_checks, uptime_daily_summaries"
```

---

## Task 2: Models

**Files:**
- Create: `app/models/uptime_monitor.rb`
- Create: `app/models/uptime_check.rb`
- Create: `app/models/uptime_daily_summary.rb`
- Create: `spec/models/uptime_monitor_spec.rb`
- Create: `spec/models/uptime_check_spec.rb`

- [ ] **Step 1: Write UptimeMonitor model tests**

Create `spec/models/uptime_monitor_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe UptimeMonitor, type: :model do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_presence_of(:interval_seconds) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[up down degraded paused pending]) }
    it { is_expected.to validate_inclusion_of(:http_method).in_array(%w[GET HEAD POST]) }
    it { is_expected.to validate_numericality_of(:interval_seconds).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:timeout_seconds).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:expected_status_code).is_greater_than(0) }
  end

  describe 'url validation' do
    it 'rejects non-http URLs' do
      monitor = build(:uptime_monitor, project: project, url: 'ftp://example.com')
      expect(monitor).not_to be_valid
      expect(monitor.errors[:url]).to include('must start with http:// or https://')
    end

    it 'accepts https URLs' do
      monitor = build(:uptime_monitor, project: project, url: 'https://example.com/health')
      expect(monitor).to be_valid
    end
  end

  describe 'scopes' do
    it '.active returns non-paused monitors' do
      ActsAsTenant.with_tenant(account) do
        active = create(:uptime_monitor, project: project, status: 'up')
        paused = create(:uptime_monitor, project: project, status: 'paused')
        expect(UptimeMonitor.active).to include(active)
        expect(UptimeMonitor.active).not_to include(paused)
      end
    end

    it '.due_for_check returns monitors needing a check' do
      ActsAsTenant.with_tenant(account) do
        due = create(:uptime_monitor, project: project, status: 'up',
                     last_checked_at: 10.minutes.ago, interval_seconds: 300)
        not_due = create(:uptime_monitor, project: project, status: 'up',
                         last_checked_at: 1.minute.ago, interval_seconds: 300)
        never_checked = create(:uptime_monitor, project: project, status: 'pending',
                               last_checked_at: nil)
        results = UptimeMonitor.due_for_check
        expect(results).to include(due, never_checked)
        expect(results).not_to include(not_due)
      end
    end
  end

  describe '#pause! / #resume!' do
    it 'toggles status' do
      ActsAsTenant.with_tenant(account) do
        monitor = create(:uptime_monitor, project: project, status: 'up')
        monitor.pause!
        expect(monitor.reload.status).to eq('paused')
        monitor.resume!
        expect(monitor.reload.status).to eq('pending')
      end
    end
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bundle exec rspec spec/models/uptime_monitor_spec.rb
```

Expected: FAIL — `uninitialized constant UptimeMonitor`

- [ ] **Step 3: Write UptimeMonitor model**

Create `app/models/uptime_monitor.rb`:

```ruby
# frozen_string_literal: true

class UptimeMonitor < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project, optional: true
  has_many :uptime_checks, dependent: :destroy
  has_many :uptime_daily_summaries, dependent: :destroy

  encrypts :headers

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
```

- [ ] **Step 4: Create factory**

Create `spec/factories/uptime_monitors.rb`:

```ruby
FactoryBot.define do
  factory :uptime_monitor do
    association :account
    association :project
    name { "Test Monitor" }
    sequence(:url) { |n| "https://example-#{n}.com/health" }
    http_method { "GET" }
    expected_status_code { 200 }
    interval_seconds { 300 }
    timeout_seconds { 30 }
    status { "pending" }
    alert_threshold { 3 }
  end
end
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
bundle exec rspec spec/models/uptime_monitor_spec.rb
```

Expected: All green.

- [ ] **Step 6: Write UptimeCheck and UptimeDailySummary models**

Create `app/models/uptime_check.rb`:

```ruby
# frozen_string_literal: true

class UptimeCheck < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :uptime_monitor

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :recent, -> { order(created_at: :desc) }
end
```

Create `app/models/uptime_daily_summary.rb`:

```ruby
# frozen_string_literal: true

class UptimeDailySummary < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :uptime_monitor

  scope :for_period, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recent, -> { order(date: :desc) }
end
```

Create `spec/factories/uptime_checks.rb`:

```ruby
FactoryBot.define do
  factory :uptime_check do
    association :account
    association :uptime_monitor
    status_code { 200 }
    response_time_ms { 150 }
    success { true }
    region { "us-east" }
    dns_time_ms { 10 }
    connect_time_ms { 20 }
    tls_time_ms { 30 }
    ttfb_ms { 90 }
  end
end
```

- [ ] **Step 7: Write UptimeCheck model tests**

Create `spec/models/uptime_check_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe UptimeCheck, type: :model do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }
  let(:monitor) { create(:uptime_monitor, project: project) }

  describe 'scopes' do
    it '.successful returns only successful checks' do
      ActsAsTenant.with_tenant(account) do
        ok = create(:uptime_check, uptime_monitor: monitor, success: true)
        fail_check = create(:uptime_check, uptime_monitor: monitor, success: false, status_code: 500)
        expect(UptimeCheck.successful).to include(ok)
        expect(UptimeCheck.successful).not_to include(fail_check)
      end
    end
  end
end
```

- [ ] **Step 8: Run all model tests**

```bash
bundle exec rspec spec/models/uptime_monitor_spec.rb spec/models/uptime_check_spec.rb
```

Expected: All green.

- [ ] **Step 9: Commit**

```bash
git add app/models/uptime_monitor.rb app/models/uptime_check.rb app/models/uptime_daily_summary.rb spec/models/uptime_monitor_spec.rb spec/models/uptime_check_spec.rb spec/factories/uptime_monitors.rb spec/factories/uptime_checks.rb
git commit -m "feat(uptime): add UptimeMonitor, UptimeCheck, UptimeDailySummary models with tests"
```

---

## Task 3: UptimePingJob — The HTTP Check Worker

**Files:**
- Create: `app/jobs/uptime_ping_job.rb`
- Create: `spec/jobs/uptime_ping_job_spec.rb`

- [ ] **Step 1: Write UptimePingJob tests**

Create `spec/jobs/uptime_ping_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe UptimePingJob, type: :job do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }
  let(:monitor) do
    ActsAsTenant.with_tenant(account) do
      create(:uptime_monitor, project: project, status: "pending",
             url: "https://example.com/health", timeout_seconds: 5)
    end
  end

  before do
    # Stub Redis for lock
    allow(Sidekiq).to receive(:redis).and_yield(double(set: true, del: true))
  end

  describe "#perform" do
    context "when URL returns 200" do
      before do
        stub_request(:get, "https://example.com/health")
          .to_return(status: 200, body: "OK", headers: {})
      end

      it "creates a successful UptimeCheck" do
        expect {
          described_class.new.perform(monitor.id)
        }.to change { UptimeCheck.count }.by(1)

        check = UptimeCheck.last
        expect(check.success).to be true
        expect(check.status_code).to eq(200)
      end

      it "updates monitor status to up" do
        described_class.new.perform(monitor.id)
        monitor.reload
        expect(monitor.status).to eq("up")
        expect(monitor.consecutive_failures).to eq(0)
        expect(monitor.last_checked_at).to be_present
      end
    end

    context "when URL returns 500" do
      before do
        stub_request(:get, "https://example.com/health")
          .to_return(status: 500, body: "Error")
      end

      it "creates a failed UptimeCheck" do
        described_class.new.perform(monitor.id)
        check = UptimeCheck.last
        expect(check.success).to be false
        expect(check.status_code).to eq(500)
      end

      it "increments consecutive_failures" do
        described_class.new.perform(monitor.id)
        expect(monitor.reload.consecutive_failures).to eq(1)
      end
    end

    context "when URL times out" do
      before do
        stub_request(:get, "https://example.com/health").to_timeout
      end

      it "creates a failed check with error message" do
        described_class.new.perform(monitor.id)
        check = UptimeCheck.last
        expect(check.success).to be false
        expect(check.error_message).to be_present
      end
    end

    context "when consecutive failures reach alert_threshold" do
      before do
        monitor.update!(consecutive_failures: 2, status: "up", alert_threshold: 3)
        stub_request(:get, "https://example.com/health")
          .to_return(status: 500, body: "Error")
      end

      it "enqueues UptimeAlertJob on status transition" do
        expect(UptimeAlertJob).to receive(:perform_async).with(monitor.id, "down", anything)
        described_class.new.perform(monitor.id)
      end
    end

    context "when recovering from down to up" do
      before do
        monitor.update!(consecutive_failures: 5, status: "down")
        stub_request(:get, "https://example.com/health")
          .to_return(status: 200, body: "OK")
      end

      it "enqueues recovery alert" do
        expect(UptimeAlertJob).to receive(:perform_async).with(monitor.id, "up", anything)
        described_class.new.perform(monitor.id)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bundle exec rspec spec/jobs/uptime_ping_job_spec.rb
```

Expected: FAIL — `uninitialized constant UptimePingJob`

- [ ] **Step 3: Write UptimePingJob**

Create `app/jobs/uptime_ping_job.rb`:

```ruby
# frozen_string_literal: true

class UptimePingJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 1

  LOCK_TTL_BUFFER = 10 # seconds added to timeout for lock TTL
  MAX_REDIRECTS = 5

  def perform(monitor_id)
    monitor = ActsAsTenant.without_tenant { UptimeMonitor.find_by(id: monitor_id) }
    return unless monitor
    return if monitor.paused?

    # Redis lock to prevent concurrent checks on same monitor
    lock_key = "uptime_ping:#{monitor.id}"
    lock_ttl = monitor.timeout_seconds + LOCK_TTL_BUFFER

    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: lock_ttl, nx: true) }
    return unless lock_acquired

    begin
      result = perform_http_check(monitor)

      ActsAsTenant.with_tenant(monitor.account) do
        save_check_result(monitor, result)
        update_monitor_status(monitor, result)
      end
    ensure
      Sidekiq.redis { |r| r.del(lock_key) }
    end
  end

  private

  def perform_http_check(monitor)
    uri = URI.parse(monitor.url)
    result = { region: monitor.region }

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      # DNS timing
      dns_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      resolved = Addrinfo.getaddrinfo(uri.host, uri.port, nil, :STREAM)
      result[:dns_time_ms] = ms_since(dns_start)

      # Connection + TLS + Request
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = [monitor.timeout_seconds, 10].min
      http.read_timeout = monitor.timeout_seconds

      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      connect_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http.start do |conn|
        result[:connect_time_ms] = ms_since(connect_start)

        # Extract SSL expiry
        if conn.use_ssl? && conn.peer_cert
          result[:ssl_expiry] = conn.peer_cert.not_after
          result[:tls_time_ms] = ms_since(connect_start) - (result[:connect_time_ms] || 0)
        end

        request = build_request(monitor, uri)
        ttfb_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = conn.request(request)
        result[:ttfb_ms] = ms_since(ttfb_start)

        # Follow redirects
        redirect_count = 0
        while response.is_a?(Net::HTTPRedirection) && redirect_count < MAX_REDIRECTS
          redirect_count += 1
          redirect_uri = URI.parse(response['location'])
          redirect_uri = URI.join(uri, redirect_uri) unless redirect_uri.host
          request = Net::HTTP::Get.new(redirect_uri)
          response = conn.request(request)
        end

        result[:status_code] = response.code.to_i
        result[:success] = result[:status_code] == monitor.expected_status_code
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      result[:success] = false
      result[:error_message] = "Timeout: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      result[:success] = false
      result[:error_message] = "Connection error: #{e.message}"
    rescue OpenSSL::SSL::SSLError => e
      result[:success] = false
      result[:error_message] = "SSL error: #{e.message}"
    rescue StandardError => e
      result[:success] = false
      result[:error_message] = "Error: #{e.class} - #{e.message}"
    end

    result[:response_time_ms] = ms_since(start_time)
    result
  end

  def build_request(monitor, uri)
    case monitor.http_method
    when "HEAD"
      req = Net::HTTP::Head.new(uri)
    when "POST"
      req = Net::HTTP::Post.new(uri)
      req.body = monitor.body if monitor.body.present?
      req.content_type = "application/json"
    else
      req = Net::HTTP::Get.new(uri)
    end

    # Apply custom headers
    if monitor.headers.present?
      monitor.headers.each { |k, v| req[k] = v }
    end

    req["User-Agent"] = "ActiveRabbit Uptime/1.0"
    req
  end

  def save_check_result(monitor, result)
    UptimeCheck.create!(
      uptime_monitor: monitor,
      account_id: monitor.account_id,
      status_code: result[:status_code],
      response_time_ms: result[:response_time_ms]&.round,
      success: result[:success] || false,
      error_message: result[:error_message],
      region: result[:region],
      dns_time_ms: result[:dns_time_ms]&.round,
      connect_time_ms: result[:connect_time_ms]&.round,
      tls_time_ms: result[:tls_time_ms]&.round,
      ttfb_ms: result[:ttfb_ms]&.round
    )
  end

  def update_monitor_status(monitor, result)
    previous_status = monitor.status

    if result[:success]
      new_status = "up"
      monitor.update!(
        status: new_status,
        last_checked_at: Time.current,
        last_status_code: result[:status_code],
        last_response_time_ms: result[:response_time_ms]&.round,
        consecutive_failures: 0,
        ssl_expiry: result[:ssl_expiry] || monitor.ssl_expiry
      )
    else
      new_failures = monitor.consecutive_failures + 1
      new_status = new_failures >= monitor.alert_threshold ? "down" : monitor.status
      # Keep "pending" as-is until threshold hit or success
      new_status = "down" if new_failures >= monitor.alert_threshold

      monitor.update!(
        status: new_status,
        last_checked_at: Time.current,
        last_status_code: result[:status_code],
        last_response_time_ms: result[:response_time_ms]&.round,
        consecutive_failures: new_failures,
        ssl_expiry: result[:ssl_expiry] || monitor.ssl_expiry
      )
    end

    # Alert on status transitions
    if previous_status != "pending" && previous_status != new_status
      if new_status == "down" && previous_status != "down"
        UptimeAlertJob.perform_async(monitor.id, "down", { consecutive_failures: monitor.consecutive_failures })
      elsif new_status == "up" && previous_status == "down"
        UptimeAlertJob.perform_async(monitor.id, "up", { previous_status: previous_status })
      end
    end
  end

  def ms_since(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
```

- [ ] **Step 4: Create stub UptimeAlertJob (needed for tests)**

Create `app/jobs/uptime_alert_job.rb` (minimal stub for now):

```ruby
# frozen_string_literal: true

class UptimeAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  def perform(monitor_id, alert_type, payload = {})
    # Full implementation in Task 5
  end
end
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
bundle exec rspec spec/jobs/uptime_ping_job_spec.rb
```

Expected: All green.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/uptime_ping_job.rb app/jobs/uptime_alert_job.rb spec/jobs/uptime_ping_job_spec.rb
git commit -m "feat(uptime): add UptimePingJob with HTTP check, timing, SSL cert extraction, and Redis locking"
```

---

## Task 4: UptimeSchedulerJob — The Cron Scheduler

**Files:**
- Create: `app/jobs/uptime_scheduler_job.rb`
- Create: `spec/jobs/uptime_scheduler_job_spec.rb`
- Modify: `config/initializers/sidekiq_cron.rb`

- [ ] **Step 1: Write scheduler tests**

Create `spec/jobs/uptime_scheduler_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe UptimeSchedulerJob, type: :job do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }

  describe "#perform" do
    it "enqueues UptimePingJob for monitors due for a check" do
      ActsAsTenant.with_tenant(account) do
        due = create(:uptime_monitor, project: project, status: "up",
                     last_checked_at: 10.minutes.ago, interval_seconds: 300)
        not_due = create(:uptime_monitor, project: project, status: "up",
                         last_checked_at: 1.minute.ago, interval_seconds: 300)
        paused = create(:uptime_monitor, project: project, status: "paused")

        expect(UptimePingJob).to receive(:perform_async).with(due.id).once
        expect(UptimePingJob).not_to receive(:perform_async).with(not_due.id)
        expect(UptimePingJob).not_to receive(:perform_async).with(paused.id)

        described_class.new.perform
      end
    end

    it "enqueues monitors that have never been checked" do
      ActsAsTenant.with_tenant(account) do
        never_checked = create(:uptime_monitor, project: project, status: "pending", last_checked_at: nil)
        expect(UptimePingJob).to receive(:perform_async).with(never_checked.id)
        described_class.new.perform
      end
    end
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bundle exec rspec spec/jobs/uptime_scheduler_job_spec.rb
```

Expected: FAIL — `uninitialized constant UptimeSchedulerJob`

- [ ] **Step 3: Write UptimeSchedulerJob**

Create `app/jobs/uptime_scheduler_job.rb`:

```ruby
# frozen_string_literal: true

class UptimeSchedulerJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  def perform
    ActsAsTenant.without_tenant do
      UptimeMonitor.due_for_check.find_each do |monitor|
        UptimePingJob.perform_async(monitor.id)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bundle exec rspec spec/jobs/uptime_scheduler_job_spec.rb
```

Expected: All green.

- [ ] **Step 5: Add cron entries to sidekiq_cron.rb**

In `config/initializers/sidekiq_cron.rb`, add inside the `jobs` hash (before the closing `}`), after the `"weekly_report"` entry:

```ruby
    # ========================================
    # Uptime Monitoring
    # ========================================

    "uptime_scheduler" => {
      "cron" => "* * * * *",  # Every minute — enqueue pings for monitors due
      "class" => "UptimeSchedulerJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    "uptime_daily_rollup" => {
      "cron" => "30 2 * * *",  # Daily at 2:30 AM UTC — aggregate daily summaries
      "class" => "UptimeDailyRollupJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    "uptime_ssl_expiry_check" => {
      "cron" => "0 9 * * *",  # Daily at 9:00 AM UTC — SSL cert expiry warnings
      "class" => "UptimeSslExpiryCheckJob",
      "cron_timezone" => "America/Los_Angeles"
    }
```

- [ ] **Step 6: Commit**

```bash
git add app/jobs/uptime_scheduler_job.rb spec/jobs/uptime_scheduler_job_spec.rb config/initializers/sidekiq_cron.rb
git commit -m "feat(uptime): add UptimeSchedulerJob cron + sidekiq-cron entries"
```

---

## Task 5: UptimeAlertJob — Alert Delivery

**Files:**
- Modify: `app/jobs/uptime_alert_job.rb` (replace stub)
- Create: `spec/jobs/uptime_alert_job_spec.rb`
- Modify: `app/services/slack_notification_service.rb`

- [ ] **Step 1: Write alert job tests**

Create `spec/jobs/uptime_alert_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe UptimeAlertJob, type: :job do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }
  let(:monitor) do
    ActsAsTenant.with_tenant(account) do
      create(:uptime_monitor, project: project, name: "Prod API",
             url: "https://api.example.com", status: "down")
    end
  end

  before do
    project.update!(settings: {
      "notifications" => { "enabled" => true, "channels" => { "email" => true } }
    })
    stub_request(:post, "https://api.resend.com/emails")
      .to_return(status: 200, body: '{"id": "test"}', headers: { 'Content-Type' => 'application/json' })
  end

  describe "#perform" do
    it "sends a down alert email" do
      expect {
        described_class.new.perform(monitor.id, "down", { "consecutive_failures" => 3 })
      }.not_to raise_error
    end

    it "sends a recovery alert" do
      expect {
        described_class.new.perform(monitor.id, "up", { "previous_status" => "down" })
      }.not_to raise_error
    end

    it "skips if monitor not found" do
      expect {
        described_class.new.perform(-1, "down", {})
      }.not_to raise_error
    end

    it "rate-limits duplicate alerts via Redis" do
      allow(Sidekiq).to receive(:redis).and_yield(double(set: false))
      # Lock not acquired means alert was recently sent — skip
      expect(AlertMailer).not_to receive(:send_alert)
      described_class.new.perform(monitor.id, "down", {})
    end
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bundle exec rspec spec/jobs/uptime_alert_job_spec.rb
```

Expected: FAIL (stub doesn't implement logic)

- [ ] **Step 3: Implement UptimeAlertJob**

Replace `app/jobs/uptime_alert_job.rb`:

```ruby
# frozen_string_literal: true

class UptimeAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
  URL_PROTOCOL = Rails.env.production? ? "https" : "http"
  RATE_LIMIT_TTL = 5.minutes.to_i

  def perform(monitor_id, alert_type, payload = {})
    monitor = ActsAsTenant.without_tenant { UptimeMonitor.find_by(id: monitor_id) }
    return unless monitor

    project = monitor.project
    # Skip notification-channel delivery if no project (alerts only work for project-assigned monitors)
    return unless project&.notifications_enabled?

    # Rate limit: one alert per monitor per type per 5 minutes
    lock_key = "uptime_alert:#{monitor.id}:#{alert_type}"
    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: RATE_LIMIT_TTL, nx: true) }
    return unless lock_acquired

    ActsAsTenant.with_tenant(monitor.account) do
      send_slack_alert(project, monitor, alert_type, payload) if project.notify_via_slack?
      send_discord_alert(project, monitor, alert_type, payload) if project.notify_via_discord?
      send_email_alert(project, monitor, alert_type, payload) if project.notify_via_email?
    end
  end

  private

  def send_slack_alert(project, monitor, alert_type, payload)
    service = SlackNotificationService.new(project)
    service.send_uptime_alert(monitor, alert_type, payload)
  rescue => e
    Rails.logger.error("[UptimeAlert] Slack failed: #{e.message}")
  end

  def send_discord_alert(project, monitor, alert_type, payload)
    service = DiscordNotificationService.new(project)
    service.send_uptime_alert(monitor, alert_type, payload)
  rescue => e
    Rails.logger.error("[UptimeAlert] Discord failed: #{e.message}")
  end

  def send_email_alert(project, monitor, alert_type, payload)
    subject = alert_type == "up" ? "Monitor Recovered" : "Monitor Down"
    body = build_email_body(monitor, alert_type, payload)

    confirmed_users = project.account.users.select(&:email_confirmed?)
    confirmed_users.each_with_index do |user, index|
      sleep(0.6) if index > 0
      AlertMailer.send_alert(
        to: user.email,
        subject: "#{project.name}: #{subject} - #{monitor.name}",
        body: body,
        project: project,
        dashboard_url: "#{URL_PROTOCOL}://#{URL_HOST}/uptime/#{monitor.id}"
      ).deliver_now
    end
  rescue => e
    Rails.logger.error("[UptimeAlert] Email failed: #{e.message}")
  end

  def build_email_body(monitor, alert_type, payload)
    if alert_type == "down"
      <<~EMAIL
        UPTIME ALERT - MONITOR DOWN

        Monitor: #{monitor.name}
        URL: #{monitor.url}
        Status: DOWN
        Consecutive Failures: #{payload['consecutive_failures']}
        Last Status Code: #{monitor.last_status_code || 'N/A'}

        This monitor has failed #{payload['consecutive_failures']} consecutive checks.
      EMAIL
    else
      <<~EMAIL
        UPTIME RECOVERY - MONITOR UP

        Monitor: #{monitor.name}
        URL: #{monitor.url}
        Status: UP (recovered)
        Response Time: #{monitor.last_response_time_ms}ms

        This monitor has recovered and is responding normally.
      EMAIL
    end
  end
end
```

- [ ] **Step 4: Add Slack uptime alert method**

Add to `app/services/slack_notification_service.rb` (after `send_n_plus_one_alert` method, around line 32):

```ruby
  def send_uptime_alert(monitor, alert_type, payload)
    blocks, fallback = build_uptime_alert_blocks(monitor, alert_type, payload)
    send_blocks(blocks: blocks, fallback_text: fallback)
  end
```

Add the private builder method (inside the `private` section):

```ruby
  def build_uptime_alert_blocks(monitor, alert_type, payload)
    emoji = alert_type == "up" ? ":white_check_mark:" : ":red_circle:"
    status_text = alert_type == "up" ? "RECOVERED" : "DOWN"
    color = alert_type == "up" ? "#36a64f" : "#e01e5a"

    blocks = [
      {
        type: "header",
        text: { type: "plain_text", text: "#{emoji} Uptime #{status_text}: #{monitor.name}", emoji: true }
      },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: "*URL:*\n#{monitor.url}" },
          { type: "mrkdwn", text: "*Status:*\n#{status_text}" },
          { type: "mrkdwn", text: "*Response Time:*\n#{monitor.last_response_time_ms || 'N/A'}ms" },
          { type: "mrkdwn", text: "*Region:*\n#{monitor.region}" }
        ]
      }
    ]

    if alert_type == "down" && payload["consecutive_failures"]
      blocks << {
        type: "section",
        text: { type: "mrkdwn", text: ":warning: *#{payload['consecutive_failures']} consecutive failures*" }
      }
    end

    fallback = "Uptime #{status_text}: #{monitor.name} (#{monitor.url})"
    [blocks, fallback]
  end
```

- [ ] **Step 5: Add Discord uptime alert method**

Add to `app/services/discord_notification_service.rb` (same pattern as Slack — find the equivalent public method section):

```ruby
  def send_uptime_alert(monitor, alert_type, payload)
    emoji = alert_type == "up" ? ":white_check_mark:" : ":red_circle:"
    status_text = alert_type == "up" ? "RECOVERED" : "DOWN"

    embed = {
      title: "#{emoji} Uptime #{status_text}: #{monitor.name}",
      color: alert_type == "up" ? 0x36a64f : 0xe01e5a,
      fields: [
        { name: "URL", value: monitor.url, inline: true },
        { name: "Status", value: status_text, inline: true },
        { name: "Response Time", value: "#{monitor.last_response_time_ms || 'N/A'}ms", inline: true }
      ]
    }

    if alert_type == "down" && payload["consecutive_failures"]
      embed[:fields] << { name: "Consecutive Failures", value: payload["consecutive_failures"].to_s, inline: true }
    end

    send_embed(embed)
  end
```

- [ ] **Step 6: Run tests — verify they pass**

```bash
bundle exec rspec spec/jobs/uptime_alert_job_spec.rb
```

Expected: All green.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/uptime_alert_job.rb spec/jobs/uptime_alert_job_spec.rb app/services/slack_notification_service.rb app/services/discord_notification_service.rb
git commit -m "feat(uptime): implement UptimeAlertJob with Slack, Discord, and email delivery"
```

---

## Task 6: Rollup & Retention Jobs

**Files:**
- Create: `app/jobs/uptime_daily_rollup_job.rb`
- Create: `app/jobs/uptime_ssl_expiry_check_job.rb`
- Modify: `app/jobs/data_retention_job.rb`

- [ ] **Step 1: Write UptimeDailyRollupJob**

Create `app/jobs/uptime_daily_rollup_job.rb`:

```ruby
# frozen_string_literal: true

class UptimeDailyRollupJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  def perform
    yesterday = Date.current.yesterday

    ActsAsTenant.without_tenant do
      UptimeMonitor.find_each do |monitor|
        rollup_for_monitor(monitor, yesterday)
      end
    end
  end

  private

  def rollup_for_monitor(monitor, date)
    checks = UptimeCheck.where(uptime_monitor: monitor)
                        .where(created_at: date.beginning_of_day.utc..date.end_of_day.utc)

    return if checks.empty?

    response_times = checks.where.not(response_time_ms: nil).pluck(:response_time_ms).sort
    total = checks.count
    successful = checks.where(success: true).count

    # Calculate percentiles
    p95 = percentile(response_times, 95)
    p99 = percentile(response_times, 99)

    # Count incidents (transitions from success to failure)
    incidents = 0
    prev_success = true
    checks.order(:created_at).pluck(:success).each do |success|
      if !success && prev_success
        incidents += 1
      end
      prev_success = success
    end

    UptimeDailySummary.upsert(
      {
        uptime_monitor_id: monitor.id,
        account_id: monitor.account_id,
        date: date,
        total_checks: total,
        successful_checks: successful,
        uptime_percentage: total > 0 ? (successful.to_f / total * 100).round(2) : nil,
        avg_response_time_ms: response_times.any? ? (response_times.sum.to_f / response_times.size).round : nil,
        p95_response_time_ms: p95,
        p99_response_time_ms: p99,
        min_response_time_ms: response_times.min,
        max_response_time_ms: response_times.max,
        incidents_count: incidents,
        updated_at: Time.current
      },
      unique_by: [:uptime_monitor_id, :date]
    )
  end

  def percentile(sorted_array, p)
    return nil if sorted_array.empty?
    k = ((p / 100.0) * (sorted_array.size - 1)).ceil
    sorted_array[k]
  end
end
```

- [ ] **Step 2: Write UptimeSslExpiryCheckJob**

Create `app/jobs/uptime_ssl_expiry_check_job.rb`:

```ruby
# frozen_string_literal: true

class UptimeSslExpiryCheckJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 1

  WARN_DAYS = [30, 14, 7].freeze

  def perform
    ActsAsTenant.without_tenant do
      UptimeMonitor.active.where.not(ssl_expiry: nil).find_each do |monitor|
        days_until_expiry = (monitor.ssl_expiry.to_date - Date.current).to_i

        WARN_DAYS.each do |warn_at|
          next unless days_until_expiry <= warn_at

          lock_key = "ssl_alert:#{monitor.id}:#{warn_at}"
          lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: 24.hours.to_i, nx: true) }
          next unless lock_acquired

          UptimeAlertJob.perform_async(
            monitor.id,
            "ssl_expiry",
            { "days_until_expiry" => days_until_expiry, "ssl_expiry" => monitor.ssl_expiry.iso8601 }
          )
          break # Only one alert per monitor per run
        end
      end
    end
  end
end
```

- [ ] **Step 3: Add uptime_checks to DataRetentionJob**

In `app/jobs/data_retention_job.rb`, add a new dedicated cleanup method (do NOT add `uptime_checks` to `PURGEABLE_TABLES` since those helpers use `occurred_at` which `uptime_checks` doesn't have).

Add a new method after `delete_old_performance_events_for_accounts`:

```ruby
  def delete_old_uptime_checks(cutoff_date)
    delete_uptime_in_batches(cutoff_date)
  end

  def delete_old_uptime_checks_for_accounts(cutoff_date, account_ids)
    delete_uptime_in_batches(cutoff_date, account_ids)
  end
```

Add the helper method in the private section:

```ruby
  def delete_uptime_in_batches(cutoff_date, account_ids = nil)
    total_deleted = 0
    conn = ActiveRecord::Base.connection

    loop do
      if account_ids
        sql = ActiveRecord::Base.sanitize_sql_array([
          "DELETE FROM uptime_checks WHERE ctid IN (SELECT ctid FROM uptime_checks WHERE created_at < ? AND account_id IN (?) LIMIT ?)",
          cutoff_date.utc, account_ids, BATCH_SIZE
        ])
      else
        sql = ActiveRecord::Base.sanitize_sql_array([
          "DELETE FROM uptime_checks WHERE ctid IN (SELECT ctid FROM uptime_checks WHERE created_at < ? LIMIT ?)",
          cutoff_date.utc, BATCH_SIZE
        ])
      end

      result = conn.execute(sql)
      deleted_count = result.cmd_tuples
      total_deleted += deleted_count

      break if deleted_count == 0
      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} uptime_checks (total: #{total_deleted})"
      sleep(0.1) if deleted_count == BATCH_SIZE
    end

    total_deleted
  end
```

Call the new methods in the `perform` method — after phase 1 free plan cleanup, add:

```ruby
        uptime_deleted = delete_old_uptime_checks_for_accounts(free_cutoff, free_account_ids)
        Rails.logger.info "[DataRetention] Free plan: deleted #{uptime_deleted} uptime_checks"
```

And after phase 2 global cleanup, add:

```ruby
      uptime_deleted = delete_old_uptime_checks(global_cutoff)
      Rails.logger.info "[DataRetention] Global: deleted #{uptime_deleted} uptime_checks"
```

- [ ] **Step 4: Run existing data retention tests**

```bash
bundle exec rspec spec/jobs/data_retention_job_spec.rb
```

Expected: Existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/uptime_daily_rollup_job.rb app/jobs/uptime_ssl_expiry_check_job.rb app/jobs/data_retention_job.rb
git commit -m "feat(uptime): add daily rollup, SSL expiry check, and data retention jobs"
```

---

## Task 7: Routes & Controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/uptime_controller.rb`
- Create: `app/policies/uptime_monitor_policy.rb`
- Create: `spec/requests/uptime_spec.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, add after line 93 (after the `logs` route):

```ruby
  # Top-level Uptime routes (no /admin)
  get "uptime", to: "uptime#index", as: "uptime_index"
  get "uptime/new", to: "uptime#new", as: "new_uptime"
  post "uptime", to: "uptime#create", as: "uptime_monitors"
  get "uptime/:id", to: "uptime#show", as: "uptime_monitor"
  get "uptime/:id/edit", to: "uptime#edit", as: "edit_uptime_monitor"
  patch "uptime/:id", to: "uptime#update"
  delete "uptime/:id", to: "uptime#destroy"
  post "uptime/:id/pause", to: "uptime#pause", as: "pause_uptime_monitor"
  post "uptime/:id/resume", to: "uptime#resume", as: "resume_uptime_monitor"
  post "uptime/:id/check_now", to: "uptime#check_now", as: "check_now_uptime_monitor"
```

Add project-scoped routes after line 147 (after `project_deploys`):

```ruby
  get "projects/:project_id/uptime", to: "uptime#index", as: "project_uptime"
  get "projects/:project_id/uptime/:id", to: "uptime#show", as: "project_uptime_monitor"
```

Add slug-scoped routes after line 277 (after `project_slug_deploys`):

```ruby
  get ":project_slug/uptime", to: "uptime#index", as: "project_slug_uptime"
  get ":project_slug/uptime/:id", to: "uptime#show", as: "project_slug_uptime_monitor"
```

- [ ] **Step 2: Write Pundit policy**

Create `app/policies/uptime_monitor_policy.rb`:

```ruby
# frozen_string_literal: true

class UptimeMonitorPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def new?
    user_is_owner?
  end

  def create?
    user_is_owner?
  end

  def edit?
    user_is_owner?
  end

  def update?
    user_is_owner?
  end

  def destroy?
    user_is_owner?
  end

  def pause?
    user_is_owner?
  end

  def resume?
    user_is_owner?
  end

  def check_now?
    user_is_owner?
  end

  private

  def user_is_owner?
    user.owner?
  end
end
```

- [ ] **Step 3: Write controller**

Create `app/controllers/uptime_controller.rb`:

```ruby
# frozen_string_literal: true

class UptimeController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }
  before_action :set_monitor, only: [:show, :edit, :update, :destroy, :pause, :resume, :check_now]

  def index
    project_scope = @current_project || @project

    base_scope = if project_scope
                   project_scope.uptime_monitors
                 else
                   UptimeMonitor.where(account: current_account)
                 end

    @monitors = base_scope.order(created_at: :desc)

    # Summary stats
    @total_count = @monitors.count
    @up_count = @monitors.where(status: "up").count
    @down_count = @monitors.where(status: "down").count
    @degraded_count = @monitors.where(status: "degraded").count
    @paused_count = @monitors.where(status: "paused").count

    # 30-day uptime for each monitor
    @uptimes = UptimeDailySummary
      .where(uptime_monitor_id: @monitors.select(:id))
      .where(date: 30.days.ago.to_date..Date.current)
      .group(:uptime_monitor_id)
      .select(
        "uptime_monitor_id",
        "ROUND(AVG(uptime_percentage), 2) as avg_uptime",
        "ROUND(AVG(avg_response_time_ms)) as avg_response_time"
      )
      .index_by(&:uptime_monitor_id)
  end

  def show
    @recent_checks = @monitor.uptime_checks.recent.limit(20)
    @daily_summaries = @monitor.uptime_daily_summaries.recent.limit(30)

    # Calculate current uptime %
    @uptime_30d = @daily_summaries.any? ?
      (@daily_summaries.sum(&:uptime_percentage) / @daily_summaries.size).round(2) : nil
    @avg_response = @daily_summaries.any? ?
      @daily_summaries.filter_map(&:avg_response_time_ms).sum.to_f / @daily_summaries.filter_map(&:avg_response_time_ms).size : nil

    # Chart data (response times for last 24h)
    @chart_checks = @monitor.uptime_checks
      .where("created_at > ?", 24.hours.ago)
      .order(:created_at)
      .pluck(:created_at, :response_time_ms, :success)
  end

  def new
    @monitor = UptimeMonitor.new(
      http_method: "GET",
      expected_status_code: 200,
      interval_seconds: 300,
      timeout_seconds: 30,
      alert_threshold: 3
    )
    authorize @monitor
  end

  def create
    @monitor = UptimeMonitor.new(monitor_params)
    @monitor.project = @current_project || @project
    authorize @monitor

    unless current_account.within_quota?(:uptime_monitors)
      flash[:alert] = "You've reached your uptime monitor limit. Please upgrade your plan."
      render :new, status: :unprocessable_entity
      return
    end

    if @monitor.save
      redirect_to uptime_monitor_path(@monitor), notice: "Monitor created. First check will run shortly."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @monitor
  end

  def update
    authorize @monitor
    if @monitor.update(monitor_params)
      redirect_to uptime_monitor_path(@monitor), notice: "Monitor updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @monitor
    @monitor.destroy
    redirect_to uptime_index_path, notice: "Monitor deleted."
  end

  def pause
    authorize @monitor
    @monitor.pause!
    redirect_to uptime_monitor_path(@monitor), notice: "Monitor paused."
  end

  def resume
    authorize @monitor
    @monitor.resume!
    redirect_to uptime_monitor_path(@monitor), notice: "Monitor resumed. Next check will run shortly."
  end

  def check_now
    authorize @monitor

    # Rate limit: 1 manual check per 30 seconds
    lock_key = "check_now:#{@monitor.id}"
    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: 30, nx: true) }

    unless lock_acquired
      redirect_to uptime_monitor_path(@monitor), alert: "Please wait 30 seconds between manual checks."
      return
    end

    UptimePingJob.perform_async(@monitor.id)
    redirect_to uptime_monitor_path(@monitor), notice: "Check queued. Results will appear shortly."
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def set_monitor
    @monitor = UptimeMonitor.find(params[:id])
  end

  def monitor_params
    params.require(:uptime_monitor).permit(
      :name, :url, :http_method, :expected_status_code,
      :interval_seconds, :timeout_seconds, :alert_threshold, :body
    )
  end
end
```

- [ ] **Step 4: Write request spec**

Create `spec/requests/uptime_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe "Uptime", type: :request do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account, role: "owner") }
  let(:project) { create(:project, account: account, user: user) }

  before { sign_in user }

  describe "GET /uptime" do
    it "renders the index page" do
      get uptime_index_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /uptime/:id" do
    it "renders the show page" do
      monitor = ActsAsTenant.with_tenant(account) do
        create(:uptime_monitor, project: project)
      end
      get uptime_monitor_path(monitor)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /uptime" do
    it "creates a monitor" do
      expect {
        post uptime_monitors_path, params: {
          uptime_monitor: {
            name: "Test", url: "https://example.com",
            interval_seconds: 300, http_method: "GET",
            expected_status_code: 200, timeout_seconds: 30,
            alert_threshold: 3
          }
        }
      }.to change { UptimeMonitor.count }.by(1)
      expect(response).to redirect_to(uptime_monitor_path(UptimeMonitor.last))
    end
  end

  describe "POST /uptime/:id/pause" do
    it "pauses the monitor" do
      monitor = ActsAsTenant.with_tenant(account) do
        create(:uptime_monitor, project: project, status: "up")
      end
      post pause_uptime_monitor_path(monitor)
      expect(monitor.reload.status).to eq("paused")
    end
  end
end
```

- [ ] **Step 5: Run request tests**

```bash
bundle exec rspec spec/requests/uptime_spec.rb
```

Expected: FAIL first (no views yet), but controller logic should work. We'll add views in the next task.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/uptime_controller.rb app/policies/uptime_monitor_policy.rb spec/requests/uptime_spec.rb
git commit -m "feat(uptime): add routes, controller, Pundit policy, and request specs"
```

---

## Task 8: Views — Index & Sidebar

**Files:**
- Create: `app/views/uptime/index.html.erb`
- Create: `app/views/uptime/_monitor_row.html.erb`
- Modify: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Add Uptime to sidebar**

In `app/views/layouts/admin.html.erb`, add after line 163 (after the Performance nav item, before the commented-out Security section):

```erb
          <%= link_to uptime_index_path,
              class: "sidebar-nav-item group relative flex items-center px-4 py-3 text-gray-300 rounded-lg hover:bg-gray-800 hover:text-white transition-colors #{'bg-gray-800 text-white' if controller_name == 'uptime'}" do %>
            <svg class="w-5 h-5 mr-3 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"></path>
            </svg>
            <span data-sidebar-target="navText">Uptime</span>
            <span class="sidebar-tooltip">Uptime Monitoring</span>
          <% end %>
```

Note: The sidebar link uses `uptime_index_path` directly — no `base_uptime_path` variable needed since uptime is not project-scoped in the sidebar.

- [ ] **Step 2: Create index view**

Create `app/views/uptime/index.html.erb`:

```erb
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="flex justify-between items-center mb-8">
    <h1 class="text-2xl font-bold text-gray-900">Uptime Monitoring</h1>
    <%= link_to "Add Monitor", new_uptime_path, class: "bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 transition-colors text-sm font-medium" %>
  </div>

  <!-- Summary Cards -->
  <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Total</p>
      <p class="text-2xl font-bold text-gray-900"><%= @total_count %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Up</p>
      <p class="text-2xl font-bold text-green-600"><%= @up_count %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Down</p>
      <p class="text-2xl font-bold text-red-600"><%= @down_count %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Paused</p>
      <p class="text-2xl font-bold text-gray-400"><%= @paused_count %></p>
    </div>
  </div>

  <% if @monitors.any? %>
    <div class="bg-white rounded-lg shadow overflow-hidden">
      <table class="w-full">
        <thead>
          <tr class="bg-gray-50 border-b border-gray-200">
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">URL</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Uptime (30d)</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Avg Response</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Last Check</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <% @monitors.each do |monitor| %>
            <%= render "uptime/monitor_row", monitor: monitor, uptimes: @uptimes %>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="bg-white rounded-lg shadow p-12 text-center">
      <svg class="w-12 h-12 text-gray-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"></path>
      </svg>
      <h3 class="text-lg font-medium text-gray-900 mb-2">No monitors yet</h3>
      <p class="text-gray-500 mb-6">Add a URL to start monitoring uptime and response times.</p>
      <%= link_to "Add Your First Monitor", new_uptime_path, class: "bg-indigo-600 text-white px-6 py-2 rounded-lg hover:bg-indigo-700" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Create monitor row partial**

Create `app/views/uptime/_monitor_row.html.erb`:

```erb
<%
  uptime_data = uptimes[monitor.id]
  avg_uptime = uptime_data&.avg_uptime
  avg_response = uptime_data&.avg_response_time

  status_color = case monitor.status
                 when "up" then "bg-green-400"
                 when "down" then "bg-red-400"
                 when "degraded" then "bg-yellow-400"
                 when "paused" then "bg-gray-300"
                 else "bg-gray-300"
                 end

  uptime_color = if avg_uptime.nil? then "text-gray-400"
                 elsif avg_uptime >= 99.5 then "text-green-600"
                 elsif avg_uptime >= 99.0 then "text-yellow-600"
                 else "text-red-600"
                 end
%>

<tr class="hover:bg-gray-50">
  <td class="px-6 py-4">
    <span class="inline-block w-3 h-3 rounded-full <%= status_color %>"></span>
  </td>
  <td class="px-6 py-4">
    <%= link_to monitor.name, uptime_monitor_path(monitor), class: "text-gray-900 font-medium hover:text-indigo-600" %>
  </td>
  <td class="px-6 py-4 text-sm text-gray-500">
    <%= truncate(monitor.url.sub(%r{https?://}, ''), length: 40) %>
  </td>
  <td class="px-6 py-4 text-sm font-medium <%= uptime_color %>">
    <%= avg_uptime ? "#{avg_uptime}%" : "—" %>
  </td>
  <td class="px-6 py-4 text-sm text-gray-500">
    <%= avg_response ? "#{avg_response.to_i}ms" : "—" %>
  </td>
  <td class="px-6 py-4 text-sm text-gray-500">
    <%= monitor.last_checked_at ? time_ago_in_words(monitor.last_checked_at) + " ago" : "Never" %>
  </td>
  <td class="px-6 py-4 text-right text-sm space-x-2">
    <% if monitor.paused? %>
      <%= button_to "Resume", resume_uptime_monitor_path(monitor), method: :post, class: "text-green-600 hover:text-green-800" %>
    <% else %>
      <%= button_to "Pause", pause_uptime_monitor_path(monitor), method: :post, class: "text-yellow-600 hover:text-yellow-800" %>
    <% end %>
    <%= link_to "Edit", edit_uptime_monitor_path(monitor), class: "text-indigo-600 hover:text-indigo-800" %>
  </td>
</tr>
```

- [ ] **Step 4: Run request specs to verify index renders**

```bash
bundle exec rspec spec/requests/uptime_spec.rb
```

Expected: Index and show tests pass (show may still fail without show view).

- [ ] **Step 5: Commit**

```bash
git add app/views/uptime/index.html.erb app/views/uptime/_monitor_row.html.erb app/views/layouts/admin.html.erb
git commit -m "feat(uptime): add dashboard index view and sidebar navigation"
```

---

## Task 9: Views — Show, New, Edit, Form

**Files:**
- Create: `app/views/uptime/show.html.erb`
- Create: `app/views/uptime/new.html.erb`
- Create: `app/views/uptime/edit.html.erb`
- Create: `app/views/uptime/_form.html.erb`
- Create: `app/javascript/controllers/uptime_chart_controller.js`

- [ ] **Step 1: Create show view**

Create `app/views/uptime/show.html.erb`:

```erb
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <!-- Header -->
  <div class="bg-white rounded-lg shadow mb-6">
    <div class="px-6 py-4 flex justify-between items-start">
      <div>
        <h1 class="text-2xl font-bold text-gray-900"><%= @monitor.name %></h1>
        <p class="text-gray-500 mt-1"><%= @monitor.url %></p>
        <div class="mt-3 flex items-center space-x-3">
          <%
            badge_class = case @monitor.status
                          when "up" then "bg-green-100 text-green-800"
                          when "down" then "bg-red-100 text-red-800"
                          when "degraded" then "bg-yellow-100 text-yellow-800"
                          when "paused" then "bg-gray-100 text-gray-600"
                          else "bg-gray-100 text-gray-600"
                          end
          %>
          <span class="px-3 py-1 rounded-full text-sm font-medium <%= badge_class %>">
            <%= @monitor.status.upcase %>
          </span>
          <span class="text-sm text-gray-500">
            Checking every <%= @monitor.interval_seconds / 60 %> min
          </span>
          <% if @monitor.last_checked_at %>
            <span class="text-sm text-gray-500">
              Last checked <%= time_ago_in_words(@monitor.last_checked_at) %> ago
            </span>
          <% end %>
        </div>
      </div>
      <div class="flex items-center space-x-2">
        <%= button_to "Check Now", check_now_uptime_monitor_path(@monitor), method: :post, class: "bg-white border border-gray-300 text-gray-700 px-3 py-2 rounded-lg hover:bg-gray-50 text-sm" %>
        <% if @monitor.paused? %>
          <%= button_to "Resume", resume_uptime_monitor_path(@monitor), method: :post, class: "bg-green-600 text-white px-3 py-2 rounded-lg hover:bg-green-700 text-sm" %>
        <% else %>
          <%= button_to "Pause", pause_uptime_monitor_path(@monitor), method: :post, class: "bg-yellow-500 text-white px-3 py-2 rounded-lg hover:bg-yellow-600 text-sm" %>
        <% end %>
        <%= link_to "Edit", edit_uptime_monitor_path(@monitor), class: "bg-white border border-gray-300 text-gray-700 px-3 py-2 rounded-lg hover:bg-gray-50 text-sm" %>
        <%= button_to "Delete", uptime_monitor_path(@monitor), method: :delete, data: { turbo_confirm: "Delete this monitor?" }, class: "bg-red-600 text-white px-3 py-2 rounded-lg hover:bg-red-700 text-sm" %>
      </div>
    </div>
  </div>

  <!-- Metric Cards -->
  <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Status</p>
      <p class="text-2xl font-bold <%= @monitor.up? ? 'text-green-600' : 'text-red-600' %>"><%= @monitor.status.upcase %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Uptime (30d)</p>
      <p class="text-2xl font-bold text-gray-900"><%= @uptime_30d ? "#{@uptime_30d}%" : "—" %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">Avg Response</p>
      <p class="text-2xl font-bold text-gray-900"><%= @avg_response ? "#{@avg_response.round}ms" : "—" %></p>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-xs text-gray-500 uppercase tracking-wide">SSL Expires</p>
      <% if @monitor.ssl_expiry %>
        <% days = (@monitor.ssl_expiry.to_date - Date.current).to_i %>
        <p class="text-2xl font-bold <%= days < 14 ? 'text-red-600' : 'text-gray-900' %>"><%= days %> days</p>
      <% else %>
        <p class="text-2xl font-bold text-gray-400">—</p>
      <% end %>
    </div>
  </div>

  <!-- Response Time Chart -->
  <div class="bg-white rounded-lg shadow p-6 mb-6"
       data-controller="uptime-chart"
       data-uptime-chart-data-value="<%= @chart_checks.map { |c| { t: c[0].iso8601, ms: c[1], ok: c[2] } }.to_json %>">
    <h2 class="text-lg font-semibold text-gray-900 mb-4">Response Time (24h)</h2>
    <canvas data-uptime-chart-target="canvas" height="200"></canvas>
  </div>

  <!-- Recent Checks -->
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold text-gray-900">Recent Checks</h2>
    </div>
    <table class="w-full">
      <thead>
        <tr class="bg-gray-50 border-b border-gray-200">
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Response</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">DNS</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Connect</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">TLS</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">TTFB</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Error</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% @recent_checks.each do |check| %>
          <tr class="hover:bg-gray-50">
            <td class="px-6 py-3 text-sm text-gray-500"><%= check.created_at.strftime("%H:%M:%S") %></td>
            <td class="px-6 py-3">
              <span class="px-2 py-1 rounded-full text-xs font-medium <%= check.success ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800' %>">
                <%= check.status_code || "ERR" %>
              </span>
            </td>
            <td class="px-6 py-3 text-sm text-gray-700"><%= check.response_time_ms ? "#{check.response_time_ms}ms" : "—" %></td>
            <td class="px-6 py-3 text-sm text-gray-500"><%= check.dns_time_ms ? "#{check.dns_time_ms}ms" : "—" %></td>
            <td class="px-6 py-3 text-sm text-gray-500"><%= check.connect_time_ms ? "#{check.connect_time_ms}ms" : "—" %></td>
            <td class="px-6 py-3 text-sm text-gray-500"><%= check.tls_time_ms ? "#{check.tls_time_ms}ms" : "—" %></td>
            <td class="px-6 py-3 text-sm text-gray-500"><%= check.ttfb_ms ? "#{check.ttfb_ms}ms" : "—" %></td>
            <td class="px-6 py-3 text-sm text-red-500"><%= truncate(check.error_message, length: 50) if check.error_message %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 2: Create form partial**

Create `app/views/uptime/_form.html.erb`:

```erb
<%= form_with(model: @monitor, url: @monitor.persisted? ? uptime_monitor_path(@monitor) : uptime_monitors_path, local: true) do |form| %>
  <% if @monitor.errors.any? %>
    <div class="rounded-md bg-red-50 p-4 mb-6">
      <h3 class="text-sm font-medium text-red-800">
        <%= pluralize(@monitor.errors.count, "error") %> prevented saving:
      </h3>
      <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
        <% @monitor.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="space-y-6">
    <div>
      <%= form.label :url, "URL to Monitor", class: "block text-sm font-medium text-gray-700" %>
      <%= form.url_field :url, placeholder: "https://example.com/health", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm", required: true %>
    </div>

    <div>
      <%= form.label :name, class: "block text-sm font-medium text-gray-700" %>
      <%= form.text_field :name, placeholder: "Production API", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm", required: true %>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div>
        <%= form.label :interval_seconds, "Check Interval", class: "block text-sm font-medium text-gray-700" %>
        <%= form.select :interval_seconds, [["Every 1 min", 60], ["Every 5 min", 300], ["Every 10 min", 600]], {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" %>
      </div>

      <div>
        <%= form.label :http_method, "HTTP Method", class: "block text-sm font-medium text-gray-700" %>
        <%= form.select :http_method, ["GET", "HEAD", "POST"], {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" %>
      </div>

      <div>
        <%= form.label :expected_status_code, "Expected Status", class: "block text-sm font-medium text-gray-700" %>
        <%= form.number_field :expected_status_code, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" %>
      </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <%= form.label :timeout_seconds, "Timeout (seconds)", class: "block text-sm font-medium text-gray-700" %>
        <%= form.number_field :timeout_seconds, min: 1, max: 60, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" %>
      </div>

      <div>
        <%= form.label :alert_threshold, "Alert after N failures", class: "block text-sm font-medium text-gray-700" %>
        <%= form.select :alert_threshold, [[1, 1], [2, 2], [3, 3], [5, 5]], {}, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" %>
      </div>
    </div>

    <div>
      <%= form.submit @monitor.persisted? ? "Update Monitor" : "Create Monitor", class: "w-full bg-indigo-600 text-white py-2 px-4 rounded-lg hover:bg-indigo-700 transition-colors font-medium cursor-pointer" %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 3: Create new and edit wrappers**

Create `app/views/uptime/new.html.erb`:

```erb
<div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <h1 class="text-2xl font-bold text-gray-900 mb-6">Add Monitor</h1>
  <div class="bg-white rounded-lg shadow p-6">
    <%= render "form" %>
  </div>
</div>
```

Create `app/views/uptime/edit.html.erb`:

```erb
<div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <h1 class="text-2xl font-bold text-gray-900 mb-6">Edit Monitor: <%= @monitor.name %></h1>
  <div class="bg-white rounded-lg shadow p-6">
    <%= render "form" %>
  </div>
</div>
```

- [ ] **Step 4: Create Stimulus chart controller**

Create `app/javascript/controllers/uptime_chart_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas"]
  static values = { data: Array }

  connect() {
    this.drawChart()
  }

  drawChart() {
    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    const data = this.dataValue

    if (!data || data.length === 0) {
      ctx.font = "14px sans-serif"
      ctx.fillStyle = "#9ca3af"
      ctx.textAlign = "center"
      ctx.fillText("No data yet", canvas.width / 2, canvas.height / 2)
      return
    }

    // Set canvas size
    const rect = canvas.parentElement.getBoundingClientRect()
    canvas.width = rect.width
    canvas.height = 200

    const padding = { top: 20, right: 20, bottom: 30, left: 50 }
    const chartWidth = canvas.width - padding.left - padding.right
    const chartHeight = canvas.height - padding.top - padding.bottom

    const times = data.map(d => new Date(d.t).getTime())
    const values = data.map(d => d.ms || 0)
    const maxMs = Math.max(...values) * 1.1 || 100

    // Draw axes
    ctx.strokeStyle = "#e5e7eb"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(padding.left, padding.top)
    ctx.lineTo(padding.left, canvas.height - padding.bottom)
    ctx.lineTo(canvas.width - padding.right, canvas.height - padding.bottom)
    ctx.stroke()

    // Y-axis labels
    ctx.fillStyle = "#6b7280"
    ctx.font = "11px sans-serif"
    ctx.textAlign = "right"
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (chartHeight * (4 - i) / 4)
      const label = Math.round(maxMs * i / 4)
      ctx.fillText(`${label}ms`, padding.left - 8, y + 4)
    }

    // Draw line
    const minTime = Math.min(...times)
    const maxTime = Math.max(...times)
    const timeRange = maxTime - minTime || 1

    ctx.beginPath()
    ctx.strokeStyle = "#6366f1"
    ctx.lineWidth = 2
    data.forEach((d, i) => {
      const x = padding.left + ((times[i] - minTime) / timeRange) * chartWidth
      const y = padding.top + chartHeight - ((d.ms || 0) / maxMs) * chartHeight
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()

    // Draw failure dots
    data.forEach((d, i) => {
      if (!d.ok) {
        const x = padding.left + ((times[i] - minTime) / timeRange) * chartWidth
        const y = padding.top + chartHeight
        ctx.beginPath()
        ctx.fillStyle = "#ef4444"
        ctx.arc(x, y, 4, 0, Math.PI * 2)
        ctx.fill()
      }
    })
  }
}
```

- [ ] **Step 5: Run all request specs**

```bash
bundle exec rspec spec/requests/uptime_spec.rb
```

Expected: All green.

- [ ] **Step 6: Commit**

```bash
git add app/views/uptime/ app/javascript/controllers/uptime_chart_controller.js
git commit -m "feat(uptime): add show, new, edit views with response time chart"
```

---

## Task 10: Add has_many :uptime_monitors to Project model

**Files:**
- Modify: `app/models/project.rb`

- [ ] **Step 1: Add association to Project**

In `app/models/project.rb`, add in the associations section:

```ruby
  has_many :uptime_monitors, dependent: :destroy
```

- [ ] **Step 2: Verify existing tests still pass**

```bash
bundle exec rspec spec/models/project_spec.rb
```

Expected: All green.

- [ ] **Step 3: Commit**

```bash
git add app/models/project.rb
git commit -m "feat(uptime): add has_many :uptime_monitors to Project"
```

---

## Task 11: Final Integration Test & Verification

- [ ] **Step 1: Run the full test suite**

```bash
bundle exec rspec
```

Expected: All existing + new tests pass.

- [ ] **Step 2: Start the app and verify manually**

```bash
rails server
```

Check:
- `/uptime` — dashboard renders with empty state
- Sidebar shows "Uptime" between "Performance" and "Deploys"
- `/uptime/new` — form renders, create works
- `/uptime/:id` — show page renders
- Pause/Resume/Edit/Delete work

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix(uptime): integration fixes from manual testing"
```
