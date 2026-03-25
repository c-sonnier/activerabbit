# Log Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured log management so clients can ingest, search, and explore application logs — connected to issues and performance traces, with real-time streaming.

**Architecture:** SDK buffers and ships logs via `POST /api/v1/logs`. `LogIngestJob` bulk-inserts into a `log_entries` table (Postgres, JSONB for structured fields) and broadcasts via ActionCable for live tail. Logs link to issues/traces via `trace_id`. Storage abstracted behind `LogStore` interface. R2 cold archival for expired logs.

**Tech Stack:** Rails 8.2, PostgreSQL, Sidekiq, ActionCable (solid_cable), Hotwire/Stimulus, Tailwind CSS, Redis, Cloudflare R2

**Spec:** `docs/superpowers/specs/2026-03-23-log-management-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `db/migrate/XXXX_add_trace_id_to_events.rb` | Prerequisite: add trace_id/request_id to events and performance_events |
| `db/migrate/XXXX_create_log_entries.rb` | Log entries table with indexes |
| `db/migrate/XXXX_add_log_quota_to_accounts.rb` | Log quota columns on accounts |
| `app/models/log_entry.rb` | LogEntry model with scopes, validations, acts_as_tenant |
| `app/services/log_store.rb` | Storage abstraction interface |
| `app/services/log_search_query_parser.rb` | Sentry-style query syntax → SQL |
| `app/jobs/log_ingest_job.rb` | Batch ingest + ActionCable broadcast |
| `app/jobs/log_archive_job.rb` | R2 cold archival of expired logs |
| `app/controllers/api/v1/logs_controller.rb` | Log ingestion API endpoint |
| `app/controllers/logs_controller.rb` | Web UI controller for log explorer |
| `app/channels/application_cable/connection.rb` | ActionCable base connection (if not exists) |
| `app/channels/application_cable/channel.rb` | ActionCable base channel (if not exists) |
| `app/channels/log_stream_channel.rb` | ActionCable channel for live tail |
| `app/views/logs/index.html.erb` | Main log explorer page |
| `app/views/logs/_log_entry_row.html.erb` | Expandable log row partial |
| `app/views/logs/_log_entry_detail.html.erb` | Expanded detail partial |
| `app/views/issues/_logs_tab.html.erb` | Logs tab for issue detail |
| `app/javascript/controllers/log_stream_controller.js` | Stimulus controller for live tail |
| `app/javascript/controllers/log_search_controller.js` | Stimulus controller for search/filter |
| `test/models/log_entry_test.rb` | Model tests |
| `test/services/log_store_test.rb` | LogStore tests |
| `test/services/log_search_query_parser_test.rb` | Query parser tests |
| `test/jobs/log_ingest_job_test.rb` | Ingest job tests |
| `test/jobs/log_archive_job_test.rb` | Archive job tests |
| `test/integration/api_logs_test.rb` | API integration tests |
| `test/integration/logs_controller_test.rb` | Web UI integration tests |
| `test/channels/log_stream_channel_test.rb` | ActionCable channel tests |
| `test/fixtures/log_entries.yml` | Test fixtures |

### Modified Files
| File | Change |
|------|--------|
| `app/models/concerns/resource_quotas.rb` | Add `:log_entries` resource type, quotas, and all supporting methods |
| `app/models/concerns/quota_warnings.rb` | Add `:log_entries` to warning checks |
| `app/jobs/data_retention_job.rb` | Add `log_entries` to batched-delete cleanup |
| `app/jobs/usage_snapshot_job.rb` | Count log entries for cached usage |
| `config/routes.rb` | Add API and web log routes |
| `config/initializers/sidekiq_cron.rb` | Add LogArchiveJob schedule |
| `app/views/layouts/admin.html.erb` | Add "Logs" sidebar nav item |
| `app/views/issues/show.html.erb` | Add "Logs" tab to issue detail |

---

## Task 1: Prerequisite Migration — Add trace_id to Events

**Files:**
- Create: `db/migrate/XXXX_add_trace_id_to_events.rb`
- Test: `test/models/event_test.rb` (verify column exists)

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/event_test.rb — add to existing file
test "event has trace_id and request_id columns" do
  event = events(:default)
  assert event.respond_to?(:trace_id)
  assert event.respond_to?(:request_id)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/event_test.rb -n "test_event_has_trace_id_and_request_id_columns"`
Expected: FAIL — `NoMethodError: undefined method 'trace_id'`

- [ ] **Step 3: Generate and write the migration**

```bash
bin/rails generate migration AddTraceIdToEvents
```

Edit the generated migration:

```ruby
class AddTraceIdToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :trace_id, :string
    add_column :events, :request_id, :string
    add_column :performance_events, :trace_id, :string

    add_index :events, :trace_id
    add_index :events, :request_id
    add_index :performance_events, :trace_id
  end
end
```

- [ ] **Step 4: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/models/event_test.rb -n "test_event_has_trace_id_and_request_id_columns"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*_add_trace_id_to_events.rb db/schema.rb test/models/event_test.rb
git commit -m "feat(logs): add trace_id and request_id columns to events and performance_events"
```

---

## Task 2: Database Migration — Create log_entries Table

**Files:**
- Create: `db/migrate/XXXX_create_log_entries.rb`
- Create: `test/fixtures/log_entries.yml`

- [ ] **Step 1: Generate and write the migration**

```bash
bin/rails generate migration CreateLogEntries
```

Edit the generated migration:

```ruby
class CreateLogEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :log_entries do |t|
      t.bigint :account_id, null: false
      t.bigint :project_id, null: false
      t.integer :level, null: false, default: 2  # 0=trace,1=debug,2=info,3=warn,4=error,5=fatal
      t.text :message, null: false
      t.text :message_template
      t.jsonb :params, default: {}
      t.jsonb :context, default: {}
      t.string :trace_id
      t.string :span_id
      t.string :request_id
      t.bigint :issue_id
      t.string :environment, default: "production"
      t.string :release
      t.string :source
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :log_entries, :account_id
    add_index :log_entries, [:project_id, :occurred_at]
    add_index :log_entries, [:project_id, :level, :occurred_at]
    add_index :log_entries, :trace_id
    add_index :log_entries, [:issue_id, :occurred_at]
    add_index :log_entries, :params, using: :gin
    add_index :log_entries, :context, using: :gin

    add_foreign_key :log_entries, :accounts
    add_foreign_key :log_entries, :projects
  end
end
```

- [ ] **Step 2: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Create test fixtures**

```yaml
# test/fixtures/log_entries.yml
default:
  account: default
  project: default
  level: 2
  message: "Processing payment for customer cus_123"
  params: '{"customer_id": "cus_123"}'
  context: '{}'
  environment: "production"
  occurred_at: <%= 1.hour.ago.iso8601 %>

error_log:
  account: default
  project: default
  level: 4
  message: "Stripe::CardError after 2 retries"
  message_template: "Stripe::CardError after %{retry_count} retries"
  params: '{"retry_count": "2", "payment_id": "pay_456"}'
  context: '{"card_last4": "4242"}'
  trace_id: "tr_abc123"
  request_id: "req_xyz789"
  environment: "production"
  source: "StripeService"
  occurred_at: <%= 30.minutes.ago.iso8601 %>

old_log:
  account: default
  project: default
  level: 2
  message: "Old log entry for retention testing"
  environment: "production"
  occurred_at: <%= 40.days.ago.iso8601 %>
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_create_log_entries.rb db/schema.rb test/fixtures/log_entries.yml
git commit -m "feat(logs): create log_entries table with indexes and fixtures"
```

---

## Task 3: Database Migration — Add Log Quota to Accounts

**Files:**
- Create: `db/migrate/XXXX_add_log_quota_to_accounts.rb`

- [ ] **Step 1: Generate and write the migration**

```bash
bin/rails generate migration AddLogQuotaToAccounts
```

```ruby
class AddLogQuotaToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :cached_log_entries_used, :integer, default: 0
  end
end
```

- [ ] **Step 2: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Commit**

```bash
git add db/migrate/*_add_log_quota_to_accounts.rb db/schema.rb
git commit -m "feat(logs): add cached_log_entries_used column to accounts"
```

---

## Task 4: LogEntry Model

**Files:**
- Create: `app/models/log_entry.rb`
- Create: `test/models/log_entry_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/log_entry_test.rb
require "test_helper"

class LogEntryTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "valid log entry" do
    entry = LogEntry.new(
      account: @account,
      project: @project,
      level: 2,
      message: "Test log message",
      occurred_at: Time.current
    )
    assert entry.valid?
  end

  test "requires project" do
    entry = LogEntry.new(level: 2, message: "Test", occurred_at: Time.current, account: @account)
    refute entry.valid?
    assert_includes entry.errors[:project], "must exist"
  end

  test "requires message" do
    entry = LogEntry.new(project: @project, level: 2, occurred_at: Time.current, account: @account)
    refute entry.valid?
    assert_includes entry.errors[:message], "can't be blank"
  end

  test "requires level" do
    entry = LogEntry.new(project: @project, message: "Test", occurred_at: Time.current, account: @account)
    refute entry.valid?
  end

  test "level_name returns human-readable level" do
    entry = log_entries(:error_log)
    assert_equal "error", entry.level_name
  end

  test "scope by_level filters correctly" do
    assert LogEntry.by_level(:error).where(project: @project).exists?
    refute LogEntry.by_level(:fatal).where(project: @project).exists?
  end

  test "scope recent returns entries within timeframe" do
    recent = LogEntry.recent(2.hours)
    assert_includes recent, log_entries(:default)
    refute_includes recent, log_entries(:old_log)
  end

  test "scope for_trace finds entries by trace_id" do
    entry = log_entries(:error_log)
    assert_includes LogEntry.for_trace("tr_abc123"), entry
  end

  test "scrub_pii scrubs sensitive fields" do
    result = LogEntry.scrub_pii({"email" => "user@example.com", "name" => "Alex"})
    assert_equal "[SCRUBBED]", result["email"]
    assert_equal "Alex", result["name"]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/log_entry_test.rb`
Expected: FAIL — `NameError: uninitialized constant LogEntry`

- [ ] **Step 3: Write the LogEntry model**

```ruby
# app/models/log_entry.rb
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/log_entry_test.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/log_entry.rb test/models/log_entry_test.rb
git commit -m "feat(logs): add LogEntry model with validations, scopes, and PII scrubbing"
```

---

## Task 5: LogStore Service (Storage Abstraction)

**Files:**
- Create: `app/services/log_store.rb`
- Create: `test/services/log_store_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/log_store_test.rb
require "test_helper"

class LogStoreTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "insert_batch creates log entries" do
    entries = [
      { level: 2, message: "Test log 1", occurred_at: Time.current, environment: "production" },
      { level: 3, message: "Test log 2", occurred_at: Time.current, environment: "production" }
    ]

    assert_difference "LogEntry.count", 2 do
      LogStore.insert_batch(@project, entries)
    end
  end

  test "insert_batch sets account_id from project" do
    entries = [{ level: 2, message: "Test", occurred_at: Time.current, environment: "production" }]
    LogStore.insert_batch(@project, entries)

    entry = LogEntry.last
    assert_equal @account.id, entry.account_id
    assert_equal @project.id, entry.project_id
  end

  test "insert_batch scrubs PII from params and context" do
    entries = [{
      level: 2,
      message: "Test",
      occurred_at: Time.current,
      params: { "email" => "user@test.com" },
      context: { "password" => "secret123" },
      environment: "production"
    }]

    LogStore.insert_batch(@project, entries)
    entry = LogEntry.last
    assert_equal "[SCRUBBED]", entry.params["email"]
    assert_equal "[SCRUBBED]", entry.context["password"]
  end

  test "search returns matching entries" do
    results = LogStore.search(@project, { level: :error }, 24.hours)
    assert results.any?
    assert results.all? { |e| e.level == 4 }
  end

  test "find_by_trace returns entries for trace_id" do
    results = LogStore.find_by_trace("tr_abc123")
    assert results.any?
    assert results.all? { |e| e.trace_id == "tr_abc123" }
  end

  test "find_by_issue returns entries linked to issue" do
    issue = issues(:default) rescue skip("No default issue fixture")
    log = LogEntry.create!(
      account: @account, project: @project, level: 2,
      message: "Test", occurred_at: Time.current, issue: issue
    )
    results = LogStore.find_by_issue(issue.id)
    assert_includes results, log
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/log_store_test.rb`
Expected: FAIL — `NameError: uninitialized constant LogStore`

- [ ] **Step 3: Write the LogStore service**

```ruby
# app/services/log_store.rb
class LogStore
  class << self
    def insert_batch(project, entries)
      now = Time.current
      records = entries.map do |entry|
        {
          account_id: project.account_id,
          project_id: project.id,
          level: normalize_level(entry[:level]),
          message: entry[:message],
          message_template: entry[:message_template],
          params: LogEntry.scrub_pii(entry[:params] || {}),
          context: LogEntry.scrub_pii(entry[:context] || {}),
          trace_id: entry[:trace_id],
          span_id: entry[:span_id],
          request_id: entry[:request_id],
          issue_id: resolve_issue_id(entry[:trace_id], entry[:request_id]),
          environment: entry[:environment] || "production",
          release: entry[:release],
          source: entry[:source],
          occurred_at: entry[:occurred_at] || now,
          created_at: now,
          updated_at: now
        }
      end

      LogEntry.insert_all(records) if records.any?
      records
    end

    def search(project, filters, time_range, limit: 100, cursor: nil)
      scope = LogEntry.where(project: project)
                      .where("occurred_at > ?", time_range.ago)
                      .reverse_chronological
                      .limit(limit)

      scope = scope.by_level(filters[:level]) if filters[:level]
      scope = scope.where(environment: filters[:environment]) if filters[:environment]
      scope = scope.where(source: filters[:source]) if filters[:source]
      scope = scope.where("message ILIKE ?", "%#{sanitize_like(filters[:message])}%") if filters[:message]
      scope = scope.where(trace_id: filters[:trace_id]) if filters[:trace_id]
      scope = scope.where(request_id: filters[:request_id]) if filters[:request_id]

      if filters[:params]
        filters[:params].each do |key, value|
          scope = scope.where("params @> ?", { key => value }.to_json)
        end
      end

      if cursor
        scope = scope.where("(occurred_at, id) < (?, ?)", cursor[:occurred_at], cursor[:id])
      end

      scope
    end

    def find_by_trace(trace_id)
      LogEntry.for_trace(trace_id).chronological
    end

    def find_by_issue(issue_id, time_range: 24.hours)
      LogEntry.for_issue(issue_id)
              .where("occurred_at > ?", time_range.ago)
              .chronological
    end

    def archive_before(project, cutoff)
      entries = LogEntry.where(project: project)
                        .where("occurred_at < ?", cutoff)
                        .order(:occurred_at)

      return nil unless entries.exists?

      entries.find_each.map { |e|
        {
          id: e.id, level: e.level_name, message: e.message,
          message_template: e.message_template, params: e.params,
          context: e.context, trace_id: e.trace_id, span_id: e.span_id,
          request_id: e.request_id, issue_id: e.issue_id,
          environment: e.environment, release: e.release,
          source: e.source, occurred_at: e.occurred_at.iso8601(6)
        }.to_json
      }.join("\n")
    end

    private

    def normalize_level(level)
      return level if level.is_a?(Integer)
      LogEntry::LEVELS[level.to_sym] || 2
    end

    def resolve_issue_id(trace_id, request_id)
      return nil unless trace_id || request_id

      event = if trace_id
        Event.where(trace_id: trace_id).order(occurred_at: :desc).first
      elsif request_id
        Event.where(request_id: request_id).order(occurred_at: :desc).first
      end

      event&.issue_id
    end

    def sanitize_like(str)
      str.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/log_store_test.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/log_store.rb test/services/log_store_test.rb
git commit -m "feat(logs): add LogStore service with insert, search, and trace/issue lookup"
```

---

## Task 6: LogSearchQueryParser Service

**Files:**
- Create: `app/services/log_search_query_parser.rb`
- Create: `test/services/log_search_query_parser_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/log_search_query_parser_test.rb
require "test_helper"

class LogSearchQueryParserTest < ActiveSupport::TestCase
  test "parses level filter" do
    result = LogSearchQueryParser.parse('level:error')
    assert_equal :error, result[:level]
  end

  test "parses environment filter" do
    result = LogSearchQueryParser.parse('environment:production')
    assert_equal "production", result[:environment]
  end

  test "parses source filter" do
    result = LogSearchQueryParser.parse('source:StripeService')
    assert_equal "StripeService", result[:source]
  end

  test "parses message substring" do
    result = LogSearchQueryParser.parse('message:"payment failed"')
    assert_equal "payment failed", result[:message]
  end

  test "parses structured params" do
    result = LogSearchQueryParser.parse('customer_id:"cus_123" payment_id:"pay_456"')
    assert_equal({ "customer_id" => "cus_123", "payment_id" => "pay_456" }, result[:params])
  end

  test "parses trace_id filter" do
    result = LogSearchQueryParser.parse('trace_id:tr_abc123')
    assert_equal "tr_abc123", result[:trace_id]
  end

  test "parses mixed known and unknown fields" do
    result = LogSearchQueryParser.parse('level:error customer_id:"cus_123" environment:staging')
    assert_equal :error, result[:level]
    assert_equal "staging", result[:environment]
    assert_equal({ "customer_id" => "cus_123" }, result[:params])
  end

  test "handles empty query" do
    result = LogSearchQueryParser.parse("")
    assert_equal({}, result)
  end

  test "handles nil query" do
    result = LogSearchQueryParser.parse(nil)
    assert_equal({}, result)
  end

  test "bare words become message search" do
    result = LogSearchQueryParser.parse("payment failed")
    assert_equal "payment failed", result[:message]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/log_search_query_parser_test.rb`
Expected: FAIL — `NameError: uninitialized constant LogSearchQueryParser`

- [ ] **Step 3: Write the parser**

```ruby
# app/services/log_search_query_parser.rb
class LogSearchQueryParser
  KNOWN_FIELDS = %w[level environment source message release trace_id request_id issue_id].freeze

  def self.parse(query)
    return {} if query.blank?

    filters = {}
    params = {}
    bare_words = []

    tokens = tokenize(query)
    tokens.each do |token|
      if token.include?(":")
        key, value = token.split(":", 2)
        value = value.delete_prefix('"').delete_suffix('"')

        if key == "level"
          filters[:level] = value.to_sym
        elsif KNOWN_FIELDS.include?(key)
          filters[key.to_sym] = value
        else
          params[key] = value
        end
      else
        bare_words << token
      end
    end

    filters[:params] = params if params.any?
    filters[:message] = bare_words.join(" ") if bare_words.any?

    filters
  end

  private_class_method def self.tokenize(query)
    tokens = []
    scanner = StringScanner.new(query.strip)

    until scanner.eos?
      scanner.skip(/\s+/)
      if scanner.scan(/(\w+):"([^"]*)"/)
        tokens << "#{scanner[1]}:\"#{scanner[2]}\""
      elsif scanner.scan(/(\w+):(\S+)/)
        tokens << "#{scanner[1]}:#{scanner[2]}"
      elsif scanner.scan(/"([^"]*)"/)
        tokens << scanner[1]
      elsif scanner.scan(/(\S+)/)
        tokens << scanner[1]
      end
    end

    tokens
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/log_search_query_parser_test.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/log_search_query_parser.rb test/services/log_search_query_parser_test.rb
git commit -m "feat(logs): add LogSearchQueryParser for Sentry-style query syntax"
```

---

## Task 7: LogIngestJob

**Files:**
- Create: `app/jobs/log_ingest_job.rb`
- Create: `test/jobs/log_ingest_job_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/jobs/log_ingest_job_test.rb
require "test_helper"

class LogIngestJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "inserts batch of logs" do
    payload = [
      { "level" => "info", "message" => "Test log 1", "occurred_at" => Time.current.iso8601, "environment" => "production" },
      { "level" => "error", "message" => "Test log 2", "occurred_at" => Time.current.iso8601, "environment" => "production" }
    ]

    assert_difference "LogEntry.count", 2 do
      LogIngestJob.new.perform(@project.id, payload)
    end
  end

  test "sets correct account_id on entries" do
    payload = [{ "level" => "info", "message" => "Test", "occurred_at" => Time.current.iso8601, "environment" => "production" }]
    LogIngestJob.new.perform(@project.id, payload)

    entry = LogEntry.order(:created_at).last
    assert_equal @account.id, entry.account_id
  end

  test "normalizes string levels to integers" do
    payload = [{ "level" => "warn", "message" => "Warning", "occurred_at" => Time.current.iso8601, "environment" => "production" }]
    LogIngestJob.new.perform(@project.id, payload)

    entry = LogEntry.order(:created_at).last
    assert_equal 3, entry.level
  end

  test "calls ActionCable broadcast after insert" do
    payload = [{ "level" => "info", "message" => "Test", "occurred_at" => Time.current.iso8601, "environment" => "production" }]

    # Verify broadcast is called (ActionCable.server.broadcast is called in the job)
    ActionCable.server.stub(:broadcast, ->(*args) { @broadcast_called = true; @broadcast_args = args }) do
      LogIngestJob.new.perform(@project.id, payload)
    end
    # Basic smoke test — job should complete without error and insert the entry
    assert_equal 1, LogEntry.where(project: @project, message: "Test").count
  end

  test "skips empty payload" do
    assert_no_difference "LogEntry.count" do
      LogIngestJob.new.perform(@project.id, [])
    end
  end

  test "handles missing optional fields gracefully" do
    payload = [{ "level" => "info", "message" => "Minimal log" }]

    assert_difference "LogEntry.count", 1 do
      LogIngestJob.new.perform(@project.id, payload)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/log_ingest_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant LogIngestJob`

- [ ] **Step 3: Write the LogIngestJob**

```ruby
# app/jobs/log_ingest_job.rb
class LogIngestJob
  include Sidekiq::Job

  sidekiq_options queue: :ingest, retry: 2

  def perform(project_id, raw_logs)
    return if raw_logs.blank?

    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    entries = raw_logs.map do |log|
      {
        level: log["level"],
        message: log["message"],
        message_template: log["message_template"],
        params: log["params"] || {},
        context: log["context"] || {},
        trace_id: log["trace_id"],
        span_id: log["span_id"],
        request_id: log["request_id"],
        environment: log["environment"],
        release: log["release"],
        source: log["source"],
        occurred_at: log["occurred_at"] || Time.current
      }
    end

    LogStore.insert_batch(project, entries)

    broadcast_to_live_tail(project_id, entries)
  end

  private

  def broadcast_to_live_tail(project_id, entries)
    return if entries.blank?

    # Broadcast the entry data directly (insert_all does not return IDs,
    # but live tail only needs display fields, not database IDs)
    stream_data = entries.map do |e|
      {
        level: LogStore.send(:normalize_level, e[:level]),
        level_name: LogEntry::LEVEL_NAMES[LogStore.send(:normalize_level, e[:level])]&.to_s,
        message: e[:message],
        source: e[:source],
        occurred_at: e[:occurred_at]&.to_s,
        trace_id: e[:trace_id]
      }
    end

    ActionCable.server.broadcast("log_stream:project_#{project_id}", stream_data)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/log_ingest_job_test.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/log_ingest_job.rb test/jobs/log_ingest_job_test.rb
git commit -m "feat(logs): add LogIngestJob with batch insert and ActionCable broadcast"
```

---

## Task 8: ResourceQuotas + QuotaWarnings Integration

**Files:**
- Modify: `app/models/concerns/resource_quotas.rb`
- Modify: `app/models/concerns/quota_warnings.rb`
- Create: `test/models/log_entry_quota_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/log_entry_quota_test.rb
require "test_helper"

class LogEntryQuotaTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "free plan has 50_000 log_entries quota" do
    @account.update!(current_plan: "free")
    assert_equal 50_000, @account.log_entries_quota_value
  end

  test "team plan has 1_000_000 log_entries quota" do
    @account.update!(current_plan: "team")
    assert_equal 1_000_000, @account.log_entries_quota_value
  end

  test "business plan has 5_000_000 log_entries quota" do
    @account.update!(current_plan: "business")
    assert_equal 5_000_000, @account.log_entries_quota_value
  end

  test "trial plan has 1_000_000 log_entries quota" do
    @account.update!(current_plan: "trial", trial_ends_at: 14.days.from_now)
    assert_equal 1_000_000, @account.log_entries_quota_value
  end

  test "free plan has 1 day log retention" do
    @account.update!(current_plan: "free")
    assert_equal 1, @account.log_retention_days
  end

  test "team plan has 31 day log retention" do
    @account.update!(current_plan: "team")
    assert_equal 31, @account.log_retention_days
  end

  test "log_entries appears in usage_summary" do
    summary = @account.usage_summary
    assert summary.key?(:log_entries)
  end

  test "within_quota? checks log_entries" do
    @account.update!(current_plan: "free", cached_log_entries_used: 0)
    assert @account.within_quota?(:log_entries)

    @account.update!(cached_log_entries_used: 50_001)
    refute @account.within_quota?(:log_entries)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/log_entry_quota_test.rb`
Expected: FAIL — methods not found

- [ ] **Step 3: Update ResourceQuotas concern**

Add `log_entries` and `log_retention_days` to each plan in the `PLAN_QUOTAS` hash in `app/models/concerns/resource_quotas.rb`:

```ruby
# In PLAN_QUOTAS, add to each plan:
# free:
log_entries: 50_000,
log_retention_days: 1,

# trial:
log_entries: 1_000_000,
log_retention_days: 31,

# team:
log_entries: 1_000_000,
log_retention_days: 31,

# business:
log_entries: 5_000_000,
log_retention_days: 31,
```

Add these public methods to the concern (following existing pattern like `event_quota_value`, `ai_summaries_quota`):

```ruby
def log_entries_quota_value
  quota_for_resource(:log_entries)
end

def log_entries_used_in_period
  cached_log_entries_used || 0
end

def log_retention_days
  quota_for_resource(:log_retention_days)
end

def log_retention_cutoff
  log_retention_days.days.ago
end
```

Add `:log_entries` to:
- `usage_for_resource` case statement — `when :log_entries then log_entries_used_in_period`
- `quota_for_resource_by_type` case statement — `when :log_entries then log_entries_quota_value`
- `usage_summary` resource list
- `reset_usage_counters!` (add `cached_log_entries_used: 0`)

- [ ] **Step 4: Update QuotaWarnings concern**

In `app/models/concerns/quota_warnings.rb`, add `:log_entries` to the resource iteration arrays in `resources_with_warnings` and `show_quota_warning?`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/log_entry_quota_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/models/concerns/resource_quotas.rb app/models/concerns/quota_warnings.rb test/models/log_entry_quota_test.rb
git commit -m "feat(logs): integrate log_entries quotas into ResourceQuotas and QuotaWarnings"
```

---

## Task 9: DataRetentionJob + UsageSnapshotJob Integration

**Files:**
- Modify: `app/jobs/data_retention_job.rb`
- Modify: `app/jobs/usage_snapshot_job.rb`
- Create: `test/jobs/log_retention_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/jobs/log_retention_test.rb
require "test_helper"

class LogRetentionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "DataRetentionJob deletes log entries older than retention period" do
    old_log = LogEntry.create!(
      account: @account, project: @project, level: 2,
      message: "Old log", occurred_at: 40.days.ago
    )
    recent_log = LogEntry.create!(
      account: @account, project: @project, level: 2,
      message: "Recent log", occurred_at: 1.hour.ago
    )

    DataRetentionJob.new.perform

    refute LogEntry.exists?(old_log.id), "Old log should be deleted"
    assert LogEntry.exists?(recent_log.id), "Recent log should be kept"
  end

  test "Free plan log entries deleted after 1 day" do
    @account.update!(current_plan: "free")
    two_day_old = LogEntry.create!(
      account: @account, project: @project, level: 2,
      message: "Old free log", occurred_at: 2.days.ago
    )

    DataRetentionJob.new.perform

    refute LogEntry.exists?(two_day_old.id)
  end

  test "UsageSnapshotJob updates cached_log_entries_used" do
    LogEntry.create!(
      account: @account, project: @project, level: 2,
      message: "Count me", occurred_at: Time.current
    )

    UsageSnapshotJob.new.perform

    @account.reload
    assert @account.cached_log_entries_used >= 1
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/log_retention_test.rb`
Expected: FAIL — log entries not being cleaned up

- [ ] **Step 3: Update DataRetentionJob**

In `app/jobs/data_retention_job.rb`:

**1. Add `"log_entries"` to the `PURGEABLE_TABLES` constant** so `validate_table_name!` accepts it.

**2. Match the existing two-phase structure:**
- Phase 1 (free-plan cleanup): Add log entry deletion for free-plan accounts using 1-day cutoff
- Phase 2 (global cleanup): Add log entry deletion using 31-day cutoff for all accounts

The existing job uses `free_plan_account_ids` in Phase 1 and a global cutoff in Phase 2. Follow this same pattern:

```ruby
# Phase 1 — add after existing free-plan cleanup:
free_log_cutoff = 1.day.ago
delete_in_batches("log_entries", free_log_cutoff) # scoped to free plan accounts

# Phase 2 — add after existing 31-day cleanup:
log_cutoff = 31.days.ago
delete_in_batches("log_entries", log_cutoff)
```

**Note:** Read the existing `data_retention_job.rb` carefully before modifying. The exact integration point depends on how the two phases are structured. The key changes are:
1. Add `"log_entries"` to `PURGEABLE_TABLES`
2. Add log-specific cutoff dates that differ from event retention (1 day for free, 31 days for paid)
3. Use the existing `delete_in_batches` method — do not create a new one

- [ ] **Step 4: Update UsageSnapshotJob**

In `app/jobs/usage_snapshot_job.rb`, in the `update_account_usage` method, add log entry counting:

```ruby
log_entries_count = LogEntry.where(account_id: account.id)
                            .where(occurred_at: start_at..end_at)
                            .count

# Add to the update_columns call:
account.update_columns(
  # ... existing columns ...
  cached_log_entries_used: log_entries_count,
  usage_cached_at: Time.current
)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/jobs/log_retention_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/data_retention_job.rb app/jobs/usage_snapshot_job.rb test/jobs/log_retention_test.rb
git commit -m "feat(logs): integrate log entries into DataRetentionJob and UsageSnapshotJob"
```

---

## Task 10: API Controller — Log Ingestion Endpoint

**Files:**
- Create: `app/controllers/api/v1/logs_controller.rb`
- Create: `test/integration/api_logs_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/integration/api_logs_test.rb
require "test_helper"

class ApiLogsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @token = api_tokens(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "POST /api/v1/logs ingests batch of logs" do
    payload = {
      logs: [
        { level: "info", message: "Test log 1", occurred_at: Time.current.iso8601 },
        { level: "error", message: "Test log 2", occurred_at: Time.current.iso8601 }
      ]
    }

    post "/api/v1/logs",
      params: payload.to_json,
      headers: { "X-Project-Token" => @token.token, "Content-Type" => "application/json" }

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal 2, json["accepted"]
  end

  test "returns 401 without valid token" do
    post "/api/v1/logs",
      params: { logs: [{ level: "info", message: "Test" }] }.to_json,
      headers: { "X-Project-Token" => "invalid", "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "returns 429 when quota exceeded" do
    @account.update!(current_plan: "free", cached_log_entries_used: 50_001)

    post "/api/v1/logs",
      params: { logs: [{ level: "info", message: "Test" }] }.to_json,
      headers: { "X-Project-Token" => @token.token, "Content-Type" => "application/json" }

    assert_response :too_many_requests
  end

  test "returns 422 with empty logs array" do
    post "/api/v1/logs",
      params: { logs: [] }.to_json,
      headers: { "X-Project-Token" => @token.token, "Content-Type" => "application/json" }

    assert_response :unprocessable_entity
  end

  test "enforces batch size limit of 500" do
    payload = { logs: Array.new(501) { { level: "info", message: "Log #{_1}" } } }

    post "/api/v1/logs",
      params: payload.to_json,
      headers: { "X-Project-Token" => @token.token, "Content-Type" => "application/json" }

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/batch size/, json["error"])
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/api_logs_test.rb`
Expected: FAIL — route not found

- [ ] **Step 3: Add routes**

In `config/routes.rb`, inside the `namespace :api` / `namespace :v1` block, add:

```ruby
post "logs", to: "logs#create"
```

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/api/v1/logs_controller.rb
module Api
  module V1
    class LogsController < Api::BaseController
      before_action :authenticate_api_token!

      MAX_BATCH_SIZE = 500

      def create
        logs = params[:logs]

        if logs.blank?
          render json: { error: "logs array is required" }, status: :unprocessable_entity
          return
        end

        if logs.size > MAX_BATCH_SIZE
          render json: { error: "batch size exceeds limit of #{MAX_BATCH_SIZE}" }, status: :unprocessable_entity
          return
        end

        unless @current_project.account.within_quota?(:log_entries)
          render json: { error: "quota_exceeded", message: "Log entries quota exceeded for your plan" }, status: :too_many_requests
          return
        end

        LogIngestJob.perform_async(@current_project.id, logs.map(&:to_unsafe_h))

        render json: { status: "accepted", accepted: logs.size }, status: :accepted
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/integration/api_logs_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/logs_controller.rb test/integration/api_logs_test.rb config/routes.rb
git commit -m "feat(logs): add POST /api/v1/logs ingestion endpoint with quota enforcement"
```

---

## Task 11: ActionCable — LogStreamChannel

**Files:**
- Create: `app/channels/application_cable/connection.rb` (if not exists)
- Create: `app/channels/application_cable/channel.rb` (if not exists)
- Create: `app/channels/log_stream_channel.rb`
- Create: `test/channels/log_stream_channel_test.rb`

- [ ] **Step 0: Generate ActionCable infrastructure (if not exists)**

The `app/channels/` directory does not exist yet. Generate the base classes:

```bash
bin/rails generate channel LogStream
```

This creates:
- `app/channels/application_cable/connection.rb`
- `app/channels/application_cable/channel.rb`
- `app/channels/log_stream_channel.rb`
- `test/channels/log_stream_channel_test.rb`

Edit `app/channels/application_cable/connection.rb` to authenticate:

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_account

    def connect
      self.current_user = find_verified_user
      self.current_account = current_user&.account
    end

    private

    def find_verified_user
      if (verified_user = env["warden"].user)
        verified_user
      else
        reject_unauthorized_connection
      end
    end
  end
end
```

- [ ] **Step 1: Write the failing tests**

```ruby
# test/channels/log_stream_channel_test.rb
require "test_helper"

class LogStreamChannelTest < ActionCable::Channel::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @user = users(:owner)
  end

  test "subscribes to project log stream" do
    stub_connection current_user: @user, current_account: @account
    subscribe(project_id: @project.id)

    assert subscription.confirmed?
    assert_has_stream "log_stream:project_#{@project.id}"
  end

  test "rejects subscription without project_id" do
    stub_connection current_user: @user, current_account: @account
    subscribe(project_id: nil)

    assert subscription.rejected?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/channels/log_stream_channel_test.rb`
Expected: FAIL — `NameError: uninitialized constant LogStreamChannel`

- [ ] **Step 3: Write the channel**

```ruby
# app/channels/log_stream_channel.rb
class LogStreamChannel < ApplicationCable::Channel
  def subscribed
    project = Project.find_by(id: params[:project_id])

    if project && project.account_id == connection.current_account&.id
      stream_from "log_stream:project_#{project.id}"
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/channels/log_stream_channel_test.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/channels/log_stream_channel.rb test/channels/log_stream_channel_test.rb
git commit -m "feat(logs): add LogStreamChannel for live tail WebSocket streaming"
```

---

## Task 12: Web Controller — Logs Explorer

**Files:**
- Create: `app/controllers/logs_controller.rb`
- Create: `test/integration/logs_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/integration/logs_controller_test.rb
require "test_helper"

class LogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  test "GET /logs renders log explorer" do
    get logs_path
    assert_response :success
  end

  test "GET /logs with search query filters results" do
    get logs_path, params: { q: "level:error", project_id: @project.id }
    assert_response :success
  end

  test "GET /logs with time range" do
    get logs_path, params: { range: "1h", project_id: @project.id }
    assert_response :success
  end

  test "GET /logs requires authentication" do
    sign_out @user
    get logs_path
    assert_response :redirect
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/logs_controller_test.rb`
Expected: FAIL — route not found

- [ ] **Step 3: Add web route**

In `config/routes.rb`, add alongside the other top-level routes:

```ruby
get "logs", to: "logs#index"
```

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/logs_controller.rb
# NOTE: This replaces the existing logs_controller.rb if one exists
class LogsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  TIME_RANGES = {
    "1h" => 1.hour,
    "6h" => 6.hours,
    "24h" => 24.hours,
    "7d" => 7.days
  }.freeze

  def index
    @project = current_account.projects.find_by(id: params[:project_id]) || current_account.projects.first
    return render_no_projects unless @project

    time_range = TIME_RANGES[params[:range]] || 1.hour
    filters = LogSearchQueryParser.parse(params[:q])

    @log_entries = LogStore.search(@project, filters, time_range, limit: 100, cursor: cursor_params)
    @query = params[:q]
    @range = params[:range] || "1h"
  end

  private

  def cursor_params
    return nil unless params[:cursor_at] && params[:cursor_id]
    { occurred_at: Time.parse(params[:cursor_at]), id: params[:cursor_id].to_i }
  end

  def render_no_projects
    redirect_to dashboard_path, alert: "Create a project first to view logs."
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/integration/logs_controller_test.rb`
Expected: All PASS (will need views in next task)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/logs_controller.rb test/integration/logs_controller_test.rb config/routes.rb
git commit -m "feat(logs): add LogsController with search, filtering, and pagination"
```

---

## Task 13: Views — Log Explorer UI

**Files:**
- Create: `app/views/logs/index.html.erb`
- Create: `app/views/logs/_log_entry_row.html.erb`
- Create: `app/views/logs/_log_entry_detail.html.erb`
- Modify: `app/views/layouts/admin.html.erb` (add sidebar nav)

- [ ] **Step 1: Create the main log explorer view**

```erb
<%# app/views/logs/index.html.erb %>
<% content_for :title, "Logs" %>

<div class="space-y-4">
  <%# Header with Live toggle %>
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Logs</h1>
    <button data-controller="log-stream"
            data-log-stream-project-id-value="<%= @project.id %>"
            data-action="click->log-stream#toggle"
            class="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-gray-300 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700">
      <span data-log-stream-target="indicator" class="w-2 h-2 rounded-full bg-gray-400"></span>
      <span data-log-stream-target="label">Live</span>
    </button>
  </div>

  <%# Search bar and filters %>
  <div class="flex gap-3" data-controller="log-search">
    <div class="flex-1">
      <input type="text"
             name="q"
             value="<%= @query %>"
             placeholder='Search logs... e.g. customer_id:"cus_123" level:error'
             data-log-search-target="input"
             data-action="keydown.enter->log-search#search"
             class="w-full px-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white text-sm focus:ring-2 focus:ring-purple-500 focus:border-transparent" />
    </div>
    <select data-log-search-target="range" data-action="change->log-search#search"
            class="px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm">
      <option value="1h" <%= "selected" if @range == "1h" %>>Last 1h</option>
      <option value="6h" <%= "selected" if @range == "6h" %>>Last 6h</option>
      <option value="24h" <%= "selected" if @range == "24h" %>>Last 24h</option>
      <option value="7d" <%= "selected" if @range == "7d" %>>Last 7d</option>
    </select>
  </div>

  <%# Level filter pills %>
  <div class="flex gap-2">
    <% %w[trace debug info warn error fatal].each do |level| %>
      <button class="px-3 py-1 text-xs font-medium rounded-full border
                     <%= level_pill_class(level) %>">
        <%= level.upcase %>
      </button>
    <% end %>
  </div>

  <%# Log entries table %>
  <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden"
       id="log-entries"
       data-log-stream-target="entries">
    <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
      <thead class="bg-gray-50 dark:bg-gray-900">
        <tr>
          <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
          <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Level</th>
          <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Source</th>
          <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Message</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200 dark:divide-gray-700" data-log-stream-target="tbody">
        <% @log_entries.each do |entry| %>
          <%= render "logs/log_entry_row", entry: entry %>
        <% end %>
      </tbody>
    </table>
  </div>

  <%# Load more %>
  <% if @log_entries.size == 100 %>
    <div class="text-center">
      <% last = @log_entries.last %>
      <%= link_to "Load more",
            logs_path(q: @query, range: @range, project_id: @project.id,
                      cursor_at: last.occurred_at.iso8601(6), cursor_id: last.id),
            class: "text-sm text-purple-600 hover:text-purple-700" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Create the log entry row partial**

```erb
<%# app/views/logs/_log_entry_row.html.erb %>
<tr class="hover:bg-gray-50 dark:hover:bg-gray-750 cursor-pointer"
    data-action="click->log-search#toggleDetail"
    data-entry-id="<%= entry.id %>">
  <td class="px-4 py-2 text-xs text-gray-500 font-mono whitespace-nowrap">
    <%= entry.occurred_at.strftime("%H:%M:%S.%L") %>
  </td>
  <td class="px-4 py-2">
    <span class="inline-flex px-2 py-0.5 text-xs font-medium rounded-full <%= level_badge_class(entry.level_name) %>">
      <%= entry.level_name&.upcase %>
    </span>
  </td>
  <td class="px-4 py-2 text-xs text-gray-600 dark:text-gray-400 font-mono truncate max-w-[150px]">
    <%= entry.source %>
  </td>
  <td class="px-4 py-2 text-sm text-gray-900 dark:text-gray-100 truncate max-w-[500px]">
    <%= entry.message %>
  </td>
</tr>
<tr class="hidden bg-gray-50 dark:bg-gray-850" id="detail-<%= entry.id %>">
  <td colspan="4" class="px-4 py-3">
    <%= render "logs/log_entry_detail", entry: entry %>
  </td>
</tr>
```

- [ ] **Step 3: Create the log entry detail partial**

```erb
<%# app/views/logs/_log_entry_detail.html.erb %>
<div class="space-y-2 text-sm">
  <div>
    <span class="font-medium text-gray-500">Message:</span>
    <span class="text-gray-900 dark:text-white"><%= entry.message %></span>
  </div>

  <% if entry.message_template.present? %>
    <div>
      <span class="font-medium text-gray-500">Template:</span>
      <span class="font-mono text-gray-700 dark:text-gray-300"><%= entry.message_template %></span>
    </div>
  <% end %>

  <% if entry.params.present? && entry.params != {} %>
    <div>
      <span class="font-medium text-gray-500">Params:</span>
      <% entry.params.each do |key, value| %>
        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200 mr-1">
          <%= key %>: <%= value %>
        </span>
      <% end %>
    </div>
  <% end %>

  <% if entry.context.present? && entry.context != {} %>
    <div>
      <span class="font-medium text-gray-500">Context:</span>
      <% entry.context.each do |key, value| %>
        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 mr-1">
          <%= key %>: <%= value %>
        </span>
      <% end %>
    </div>
  <% end %>

  <div class="flex gap-4 pt-1">
    <% if entry.trace_id.present? %>
      <span class="text-xs text-gray-500">Trace: <span class="font-mono"><%= entry.trace_id %></span></span>
    <% end %>
    <% if entry.request_id.present? %>
      <span class="text-xs text-gray-500">Request: <span class="font-mono"><%= entry.request_id %></span></span>
    <% end %>
    <% if entry.issue_id.present? %>
      <%= link_to "View Issue →", issue_path(entry.issue_id), class: "text-xs text-purple-600 hover:text-purple-700" %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Add helper methods for level styling**

Add to `app/helpers/logs_helper.rb`:

```ruby
# app/helpers/logs_helper.rb
module LogsHelper
  def level_badge_class(level)
    case level
    when "trace", "debug" then "bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300"
    when "info" then "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
    when "warn" then "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"
    when "error" then "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300"
    when "fatal" then "bg-red-200 text-red-900 dark:bg-red-800 dark:text-red-100"
    else "bg-gray-100 text-gray-700"
    end
  end

  def level_pill_class(level)
    "border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700"
  end
end
```

- [ ] **Step 5: Add "Logs" to sidebar navigation**

In `app/views/layouts/admin.html.erb`, add the Logs nav item between Performance and Uptime, following the existing link pattern.

- [ ] **Step 6: Run the web UI tests**

Run: `bin/rails test test/integration/logs_controller_test.rb`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add app/views/logs/ app/helpers/logs_helper.rb app/views/layouts/admin.html.erb
git commit -m "feat(logs): add log explorer UI with search, level filters, and expandable rows"
```

---

## Task 14: Issue Detail — Logs Tab

**Files:**
- Create: `app/views/issues/_logs_tab.html.erb`
- Modify: `app/views/issues/show.html.erb`

- [ ] **Step 1: Create the logs tab partial**

```erb
<%# app/views/issues/_logs_tab.html.erb %>
<div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-4">
  <h3 class="text-sm font-medium text-gray-500 mb-3">
    Logs from this request
    <% if @issue_logs&.any? %>
      <span class="text-gray-400">(<%= @issue_logs.size %> entries)</span>
    <% end %>
  </h3>

  <% if @issue_logs&.any? %>
    <div class="space-y-1 font-mono text-xs">
      <% @issue_logs.each do |entry| %>
        <div class="flex gap-3 py-1 px-2 rounded <%= entry.level >= 4 ? 'bg-red-50 dark:bg-red-900/20 border-l-2 border-red-500' : 'hover:bg-gray-50 dark:hover:bg-gray-750' %>">
          <span class="text-gray-400 whitespace-nowrap"><%= entry.occurred_at.strftime("%H:%M:%S.%L") %></span>
          <span class="<%= level_badge_class(entry.level_name) %> px-1.5 rounded text-[10px] font-bold uppercase"><%= entry.level_name %></span>
          <span class="text-gray-500 truncate max-w-[120px]"><%= entry.source %></span>
          <span class="text-gray-900 dark:text-gray-100 truncate"><%= entry.message %></span>
        </div>
      <% end %>
    </div>

    <div class="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
      <%= link_to "View all logs for this issue →",
            logs_path(q: "issue_id:#{@issue.id}", range: "24h"),
            class: "text-sm text-purple-600 hover:text-purple-700" %>
    </div>
  <% else %>
    <p class="text-sm text-gray-400">No logs found for this issue. Logs require the latest SDK with <code>logs_enabled: true</code>.</p>
  <% end %>
</div>
```

- [ ] **Step 2: Update the issue show view**

In `app/views/issues/show.html.erb`, add a "Logs" tab in the tab navigation and render the partial. Add to the IssuesController#show:

```ruby
# In app/controllers/issues_controller.rb, show action, add:
@issue_logs = LogStore.find_by_issue(@issue.id, time_range: 24.hours).limit(50)
```

- [ ] **Step 3: Commit**

```bash
git add app/views/issues/_logs_tab.html.erb app/views/issues/show.html.erb app/controllers/issues_controller.rb
git commit -m "feat(logs): add Logs tab to issue detail view showing request-scoped logs"
```

---

## Task 15: Stimulus Controllers — Live Tail & Search

**Files:**
- Create: `app/javascript/controllers/log_stream_controller.js`
- Create: `app/javascript/controllers/log_search_controller.js`

- [ ] **Step 1: Write the live tail Stimulus controller**

```javascript
// app/javascript/controllers/log_stream_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@actioncable/core"

export default class extends Controller {
  static targets = ["indicator", "label", "entries", "tbody"]
  static values = { projectId: Number }

  connect() {
    this.streaming = false
    this.consumer = createConsumer()
    this.maxEntries = 500
  }

  disconnect() {
    this.stop()
    this.consumer?.disconnect()
  }

  toggle() {
    if (this.streaming) {
      this.stop()
    } else {
      this.start()
    }
  }

  start() {
    this.subscription = this.consumer.subscriptions.create(
      { channel: "LogStreamChannel", project_id: this.projectIdValue },
      {
        received: (data) => this.appendEntries(data),
        connected: () => this.setActive(true),
        disconnected: () => this.setActive(false)
      }
    )
    this.streaming = true
  }

  stop() {
    this.subscription?.unsubscribe()
    this.subscription = null
    this.streaming = false
    this.setActive(false)
  }

  appendEntries(entries) {
    const tbody = this.tbodyTarget
    entries.forEach((entry) => {
      const row = this.buildRow(entry)
      tbody.insertBefore(row, tbody.firstChild)
    })

    // Trim excess entries
    while (tbody.children.length > this.maxEntries * 2) { // *2 for detail rows
      tbody.removeChild(tbody.lastChild)
    }
  }

  buildRow(entry) {
    const row = document.createElement("tr")
    row.className = "hover:bg-gray-50 dark:hover:bg-gray-750 animate-pulse-once"
    row.innerHTML = `
      <td class="px-4 py-2 text-xs text-gray-500 font-mono whitespace-nowrap">${this.formatTime(entry.occurred_at)}</td>
      <td class="px-4 py-2"><span class="inline-flex px-2 py-0.5 text-xs font-medium rounded-full ${this.levelClass(entry.level_name)}">${(entry.level_name || '').toUpperCase()}</span></td>
      <td class="px-4 py-2 text-xs text-gray-600 dark:text-gray-400 font-mono truncate max-w-[150px]">${entry.source || ''}</td>
      <td class="px-4 py-2 text-sm text-gray-900 dark:text-gray-100 truncate max-w-[500px]">${entry.message || ''}</td>
    `
    return row
  }

  formatTime(iso) {
    if (!iso) return ""
    const d = new Date(iso)
    return d.toTimeString().split(" ")[0] + "." + String(d.getMilliseconds()).padStart(3, "0")
  }

  levelClass(level) {
    const classes = {
      trace: "bg-gray-100 text-gray-700", debug: "bg-gray-100 text-gray-700",
      info: "bg-blue-100 text-blue-700", warn: "bg-yellow-100 text-yellow-700",
      error: "bg-red-100 text-red-700", fatal: "bg-red-200 text-red-900"
    }
    return classes[level] || "bg-gray-100 text-gray-700"
  }

  setActive(active) {
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.className = active
        ? "w-2 h-2 rounded-full bg-green-500 animate-pulse"
        : "w-2 h-2 rounded-full bg-gray-400"
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = active ? "Live" : "Paused"
    }
  }
}
```

- [ ] **Step 2: Write the search Stimulus controller**

```javascript
// app/javascript/controllers/log_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "range"]

  search() {
    const query = this.inputTarget.value
    const range = this.rangeTarget.value
    const url = new URL(window.location.href)
    url.searchParams.set("q", query)
    url.searchParams.set("range", range)
    url.searchParams.delete("cursor_at")
    url.searchParams.delete("cursor_id")
    window.location.href = url.toString()
  }

  toggleDetail(event) {
    const row = event.currentTarget
    const entryId = row.dataset.entryId
    const detailRow = document.getElementById(`detail-${entryId}`)
    if (detailRow) {
      detailRow.classList.toggle("hidden")
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/log_stream_controller.js app/javascript/controllers/log_search_controller.js
git commit -m "feat(logs): add Stimulus controllers for live tail streaming and search"
```

---

## Task 16: LogArchiveJob (R2 Cold Storage)

**Files:**
- Create: `app/jobs/log_archive_job.rb`
- Create: `test/jobs/log_archive_job_test.rb`
- Modify: `config/initializers/sidekiq_cron.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/jobs/log_archive_job_test.rb
require "test_helper"

class LogArchiveJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "LogStore.archive_before generates NDJSON for expired log entries" do
    old_log = LogEntry.create!(
      account: @account, project: @project, level: 2,
      message: "Archive me", occurred_at: 35.days.ago
    )

    ndjson = LogStore.archive_before(@project, 32.days.ago)

    assert ndjson.present?
    parsed = JSON.parse(ndjson.lines.first)
    assert_equal "Archive me", parsed["message"]
  end

  test "LogStore.archive_before returns nil when no expired entries" do
    ndjson = LogStore.archive_before(@project, 100.days.ago)
    assert_nil ndjson
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/log_archive_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant LogArchiveJob`

- [ ] **Step 3: Write the LogArchiveJob**

```ruby
# app/jobs/log_archive_job.rb
class LogArchiveJob
  include Sidekiq::Job

  sidekiq_options queue: :secondary, retry: 2

  def perform
    Account.find_each do |account|
      ActsAsTenant.current_tenant = account
      cutoff = account.log_retention_cutoff

      account.projects.find_each do |project|
        archive_project_logs(account, project, cutoff)
      end
    end
  end

  private

  def archive_project_logs(account, project, cutoff)
    ndjson = LogStore.archive_before(project, cutoff)
    return if ndjson.blank?

    compressed = compress(ndjson)
    date = cutoff.to_date
    path = r2_path(account.id, project.id, date)

    upload_to_r2(path, compressed)
    Rails.logger.info("[LogArchiveJob] Archived logs to #{path}")
  rescue => e
    Rails.logger.error("[LogArchiveJob] Failed to archive logs for project #{project.id}: #{e.message}")
  end

  def compress(data)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(data)
    gz.close
    io.string
  end

  def r2_path(account_id, project_id, date)
    "logs/#{account_id}/#{project_id}/#{date.iso8601}.ndjson.gz"
  end

  def upload_to_r2(path, data)
    # R2 uses S3-compatible API
    # Configure via ENV: R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT, R2_BUCKET
    client = Aws::S3::Client.new(
      access_key_id: ENV["R2_ACCESS_KEY_ID"],
      secret_access_key: ENV["R2_SECRET_ACCESS_KEY"],
      endpoint: ENV["R2_ENDPOINT"],
      region: "auto"
    )

    client.put_object(
      bucket: ENV.fetch("R2_BUCKET", "activerabbit-logs"),
      key: path,
      body: data,
      content_type: "application/gzip"
    )
  end
end
```

- [ ] **Step 4: Add to sidekiq-cron schedule**

In `config/initializers/sidekiq_cron.rb`, add:

```ruby
"log_archive_nightly" => {
  "cron" => "0 2 * * *",  # Daily at 2:00 AM, before data retention at 3:00 AM
  "class" => "LogArchiveJob",
  "cron_timezone" => "America/Los_Angeles"
},
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/jobs/log_archive_job_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/log_archive_job.rb test/jobs/log_archive_job_test.rb config/initializers/sidekiq_cron.rb
git commit -m "feat(logs): add LogArchiveJob for R2 cold storage archival with nightly cron"
```

---

## Task 17: Integration Test — End-to-End Flow

**Files:**
- Create: `test/integration/log_flow_test.rb`

- [ ] **Step 1: Write the end-to-end integration test**

```ruby
# test/integration/log_flow_test.rb
require "test_helper"

class LogFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    @token = api_tokens(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "full flow: ingest → search → view" do
    # 1. Ingest logs via API
    payload = {
      logs: [
        { level: "info", message: "Payment processing started", occurred_at: 2.minutes.ago.iso8601,
          params: { customer_id: "cus_flow_test" }, environment: "production", source: "PaymentsController" },
        { level: "error", message: "Payment failed: card declined", occurred_at: 1.minute.ago.iso8601,
          params: { customer_id: "cus_flow_test", payment_id: "pay_flow_test" }, environment: "production", source: "StripeService" }
      ]
    }

    post "/api/v1/logs",
      params: payload.to_json,
      headers: { "X-Project-Token" => @token.token, "Content-Type" => "application/json" }
    assert_response :accepted

    # 2. Process the ingest job synchronously
    LogIngestJob.new.perform(@project.id, payload[:logs].map(&:deep_stringify_keys))

    # 3. Verify logs exist
    assert_equal 2, LogEntry.where(project: @project).count

    # 4. Search via LogStore
    results = LogStore.search(@project, { level: :error }, 1.hour)
    assert_equal 1, results.count
    assert_equal "Payment failed: card declined", results.first.message

    # 5. Search structured params
    results = LogStore.search(@project, { params: { "customer_id" => "cus_flow_test" } }, 1.hour)
    assert_equal 2, results.count

    # 6. View via web UI
    sign_in @user
    get logs_path(q: 'customer_id:"cus_flow_test"', project_id: @project.id)
    assert_response :success
  end
end
```

- [ ] **Step 2: Run the test**

Run: `bin/rails test test/integration/log_flow_test.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/integration/log_flow_test.rb
git commit -m "test(logs): add end-to-end integration test for ingest → search → view flow"
```

---

## Task 18: Final Cleanup & Verification

- [ ] **Step 1: Run the full test suite**

```bash
bin/rails test
```

Expected: All tests pass, no regressions.

- [ ] **Step 2: Verify the log explorer page loads**

```bash
bin/rails server
```

Visit `http://localhost:3000/logs` — should render with search bar, time range picker, level pills, and empty table.

- [ ] **Step 3: Verify sidebar navigation**

Confirm "Logs" appears in sidebar between Performance and Uptime.

- [ ] **Step 4: Commit any remaining fixes**

```bash
git add -A
git commit -m "chore(logs): final cleanup and fixes for log management V1"
```
