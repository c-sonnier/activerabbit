# Uptime Monitoring Feature Design

**Date:** 2026-03-22
**Branch:** UpTime
**Status:** Approved

## Overview

Server-side uptime/heartbeat monitoring for ActiveRabbit clients. Clients add URLs via the admin dashboard, ActiveRabbit pings them from US servers on a configurable interval, collects response metrics, and alerts on downtime. Similar to Sentry Uptime, Pingdom, or BetterStack.

## Approach

Pure Sidekiq-Cron + Net::HTTP — no new gems. Uses existing infrastructure: Sidekiq for scheduling, PostgreSQL for storage, Slack/email for alerts, Tailwind/Hotwire for UI.

---

## Data Model

### `uptime_monitors`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint FK | Multi-tenant (acts_as_tenant) |
| `project_id` | bigint FK | Optional — group by project |
| `name` | string | e.g. "Production API" |
| `url` | string | e.g. `https://example.com/health` |
| `http_method` | string | GET (default), HEAD, POST |
| `expected_status_code` | integer | 200 (default) |
| `interval_seconds` | integer | 60, 300, or 600 |
| `timeout_seconds` | integer | 30 (default) |
| `headers` | jsonb | Custom headers, encrypted via Rails `encrypts :headers` |
| `body` | text | For POST checks |
| `region` | string | `"us-east"` for now, single region per monitor |
| `status` | string | `up`, `down`, `degraded`, `paused`, `pending` |
| `last_checked_at` | datetime | |
| `last_status_code` | integer | |
| `last_response_time_ms` | integer | |
| `consecutive_failures` | integer | For alert threshold |
| `alert_threshold` | integer | Alert after N failures (default 3) |
| `ssl_expiry` | datetime | Extracted from cert |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**Note on `status` field:** This is the single source of truth for monitor state. There is no separate `enabled` boolean. `paused` status means the monitor is disabled. The `UptimeSchedulerJob` queries `WHERE status NOT IN ('paused')` to find active monitors.

**Validation:** Model validates that `status` is one of the allowed values. `pause` action sets `status: "paused"`, `resume` sets `status: "pending"`.

**Encryption:** The `headers` column uses Rails 7.1+ `encrypts :headers` (deterministic: false) to protect customer auth tokens at rest. This requires no new gems — Rails 8 has this built in. Requires `ActiveRecord::Encryption` keys in credentials.

**Indexes:** `account_id`, `[status, last_checked_at]` (for scheduler query), `project_id`

### `uptime_checks`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `uptime_monitor_id` | bigint FK | |
| `account_id` | bigint FK | Tenant scoping |
| `status_code` | integer | Null if timeout/DNS failure |
| `response_time_ms` | integer | Total request time |
| `success` | boolean | Met expected status? |
| `error_message` | text | Timeout, DNS, SSL errors |
| `region` | string | `"us-east"` |
| `dns_time_ms` | integer | DNS lookup |
| `connect_time_ms` | integer | TCP connect |
| `tls_time_ms` | integer | TLS handshake |
| `ttfb_ms` | integer | Time to first byte |
| `created_at` | datetime | |

**Indexes:** `[uptime_monitor_id, created_at]`, `[account_id, created_at]` (for retention cleanup — no project_id join needed)

**Retention:** 5 days free, 31 days paid. Cleaned up by a dedicated `delete_old_uptime_checks` method in `DataRetentionJob` that uses `account_id` directly (not via projects join), since `uptime_checks` has `account_id` as a direct column.

### `uptime_daily_summaries`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `uptime_monitor_id` | bigint FK | |
| `account_id` | bigint FK | |
| `date` | date | UTC date boundary |
| `total_checks` | integer | |
| `successful_checks` | integer | |
| `uptime_percentage` | decimal(5,2) | e.g. 99.95 |
| `avg_response_time_ms` | integer | |
| `p95_response_time_ms` | integer | |
| `p99_response_time_ms` | integer | |
| `min_response_time_ms` | integer | |
| `max_response_time_ms` | integer | |
| `incidents_count` | integer | |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**Indexes:** `[uptime_monitor_id, date]` unique, `[account_id, date]` (for index page 30-day uptime queries)

**Rollup uses `UPSERT`:** `INSERT ... ON CONFLICT (uptime_monitor_id, date) DO UPDATE` for idempotent re-runs.

---

## Jobs & Scheduling

### `UptimeSchedulerJob` (cron — every minute)

Added to `sidekiq_cron.rb`. Queries monitors due for a check using ActiveRecord:

```ruby
UptimeMonitor
  .where.not(status: "paused")
  .where("last_checked_at IS NULL OR last_checked_at <= NOW() - (interval_seconds || ' seconds')::interval")
  .find_each { |monitor| UptimePingJob.perform_async(monitor.id) }
```

Enqueues `UptimePingJob` for each. Lightweight scheduler only.

### `UptimePingJob` (Sidekiq worker)

**Concurrency lock:** Uses Redis `SET NX` with key `uptime_ping:{monitor_id}` and TTL of `timeout_seconds + 10` to prevent concurrent checks on the same monitor (from `check_now` + cron overlap). If lock not acquired, skip silently.

Steps:
1. Acquire Redis lock (skip if already locked)
2. Perform HTTP request with detailed timing (DNS, connect, TLS, TTFB) via `Net::HTTP`
3. Extract SSL cert expiry from peer certificate
4. Follow redirects (max 5)
5. Save `UptimeCheck` record
6. Update `UptimeMonitor` fields atomically: `last_checked_at`, `last_status_code`, `last_response_time_ms`, `status`, `consecutive_failures`, `ssl_expiry`
7. If status changed (up->down or down->up): trigger `UptimeAlertJob`
8. Release Redis lock

**Error handling:** DNS failure, connection refused, timeout, SSL errors — all captured in `error_message`, marked as `success: false`.

### `UptimeDailyRollupJob` (cron — 2:30 AM UTC daily)

All time boundaries use **UTC**. The `date` column in `uptime_daily_summaries` represents a UTC calendar day. The rollup aggregates checks where `created_at` falls within the UTC day boundary.

Uses `INSERT ... ON CONFLICT DO UPDATE` for idempotent re-runs.

### `UptimeSslExpiryCheckJob` (cron — 9:00 AM UTC daily)

Scans all active monitors with `ssl_expiry` set. Sends alerts at 30, 14, and 7 days before expiration. Uses Redis `SET NX` with key `ssl_alert:{monitor_id}:{days}` and TTL of 24 hours to prevent duplicate daily alerts.

---

## Alert System

### Separate from `AlertRule`/`AlertNotification`

The existing `AlertNotification` requires a `belongs_to :alert_rule` FK, and `AlertRule` validates specific `rule_type` values. Rather than force uptime alerts into this schema, uptime uses its own lightweight alert path:

### `UptimeAlertJob` (Sidekiq worker)

Triggered by `UptimePingJob` on status transitions. Handles:
- **Down alert:** When status changes to `down` (after `alert_threshold` consecutive failures)
- **Recovery alert:** When status returns to `up` — includes downtime duration
- **SSL expiry warning:** Triggered by `UptimeSslExpiryCheckJob`

**Delivery:** Directly calls `SlackNotificationService` and `DiscordNotificationService` (same services used by `AlertJob`), plus email via `AlertMailer`. No `AlertRule` or `AlertNotification` records needed.

**Rate limiting:** Redis `SET NX` with key `uptime_alert:{monitor_id}:{alert_type}` and TTL of 5 minutes prevents duplicate alerts during flapping.

**Channels:** Uses the project's existing notification preferences (`project.notify_via_slack?`, `project.notify_via_email?`, `project.notify_via_discord?`).

---

## Routes

```ruby
# config/routes.rb — inside authenticated scope, same level as errors/performance
resources :uptime, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
  member do
    post :pause
    post :resume
    post :check_now
  end
end
```

---

## Controller

`UptimeController` inherits from `Admin::ApplicationController` (Pundit authorization, acts_as_tenant scoping).

| Action | Purpose |
|--------|---------|
| `index` | Dashboard — all monitors with summary stats |
| `show` | Monitor detail — charts, checks, incidents |
| `new/create` | Add URL form (checks quota before create) |
| `edit/update` | Modify monitor settings |
| `destroy` | Delete monitor and associated checks |
| `pause` | Set `status: "paused"` |
| `resume` | Set `status: "pending"` |
| `check_now` | Enqueue immediate `UptimePingJob` (rate-limited) |

### `check_now` rate limiting

Rate-limited to 1 manual check per monitor per 30 seconds via Redis `SET NX` with key `check_now:{monitor_id}` and TTL 30s. Returns 429 with flash message if throttled. Pundit policy restricts `check_now?` to `owner` and `admin` roles (not `member`).

---

## UI Design

### Sidebar

Add "Uptime" nav item between "Performance" and "Deploys" in `app/views/layouts/admin.html.erb`. Use a signal/pulse SVG icon. Same styling as existing nav items.

### Index Page (Dashboard)

**Top row — 4 summary cards** (Tailwind, same style as Performance dashboard):
- Total Monitors (count)
- Currently Up (green)
- Currently Down (red)
- Degraded (yellow)

**Main area — monitors table:**

| Status | Name | URL | Uptime (30d) | Avg Response | Last Check | Actions |
|--------|------|-----|-------------|-------------|------------|---------|
| green dot | Production API | api.example.com | 99.98% | 142ms | 30s ago | Pause / Edit |
| red dot | Marketing Site | example.com | 97.2% | — | 2m ago | Pause / Edit |

- Status dots: green (up), red (down), yellow (degraded), gray (paused)
- Uptime color: >99.5% green, >99% yellow, <99% red
- "Add Monitor" button top-right
- Empty state with CTA when no monitors exist

### Show Page (Monitor Detail)

**Header:** Name, URL, status badge, Pause/Edit/Delete buttons

**4 metric cards:**
- Current Status (Up/Down + duration in current state)
- Uptime % (30 days)
- Avg Response Time (ms)
- SSL Expires In (days, red if <14)

**Response time chart:** Line chart (24h / 7d / 30d toggle). Uses same charting approach as Performance pages.

**Uptime bar:** Horizontal bar — 30/90 day view. Green blocks = up, red = down, gray = no data. Sentry/BetterStack style.

**Recent checks table:** Last 20 checks with status code, response time, timing breakdown (DNS/Connect/TLS/TTFB), error message.

**Incidents log:** Downtime periods with start time, end time, duration, and error details.

### New/Edit Form

Simple, fast setup:
- **URL** (required) — text input, validated format
- **Name** (required) — auto-suggested from domain on blur
- **Check interval** — select: 1 min / 5 min / 10 min
- **HTTP Method** — select: GET / HEAD / POST
- **Expected status code** — number input, default 200
- **Timeout** — number input, default 30s
- **Custom headers** — collapsible key/value pair inputs
- **Request body** — textarea, shown only when POST selected
- **Alert after** — select: 1 / 2 / 3 / 5 consecutive failures

---

## Pundit Policy

`UptimeMonitorPolicy` — scoped to current account.
- `owner` and `admin`: all actions (index, show, new, create, edit, update, destroy, pause, resume, check_now)
- `member`: read-only (index, show)

---

## Usage & Limits

Uses existing `PLAN_QUOTAS` in `resource_quotas.rb`. Current values already defined:

| Plan | `uptime_monitors` quota | Min interval |
|------|------------------------|-------------|
| `free` | 0 (not available) | N/A |
| `trial` | 20 | 1 min |
| `team` | 20 | 1 min |
| `business` | 5 | 1 min |

**Note:** The `business: 5` value is what's currently in `PLAN_QUOTAS`. If this should be higher, update `resource_quotas.rb` separately. The uptime feature will respect whatever values are in `PLAN_QUOTAS`.

The existing `within_quota?(:uptime_monitors)` and `uptime_monitors_used` methods already exist in `ResourceQuotas`. The controller checks `within_quota?(:uptime_monitors)` before allowing creation.

---

## Files to Create/Modify

### New Files
- `db/migrate/XXXX_create_uptime_monitors.rb`
- `db/migrate/XXXX_create_uptime_checks.rb`
- `db/migrate/XXXX_create_uptime_daily_summaries.rb`
- `app/models/uptime_monitor.rb`
- `app/models/uptime_check.rb`
- `app/models/uptime_daily_summary.rb`
- `app/controllers/uptime_controller.rb`
- `app/policies/uptime_monitor_policy.rb`
- `app/jobs/uptime_scheduler_job.rb`
- `app/jobs/uptime_ping_job.rb`
- `app/jobs/uptime_alert_job.rb`
- `app/jobs/uptime_daily_rollup_job.rb`
- `app/jobs/uptime_ssl_expiry_check_job.rb`
- `app/views/uptime/index.html.erb`
- `app/views/uptime/show.html.erb`
- `app/views/uptime/new.html.erb`
- `app/views/uptime/edit.html.erb`
- `app/views/uptime/_form.html.erb`
- `app/views/uptime/_monitor_row.html.erb`
- `app/javascript/controllers/uptime_chart_controller.js` (Stimulus)
- `spec/models/uptime_monitor_spec.rb`
- `spec/models/uptime_check_spec.rb`
- `spec/jobs/uptime_scheduler_job_spec.rb`
- `spec/jobs/uptime_ping_job_spec.rb`
- `spec/jobs/uptime_alert_job_spec.rb`
- `spec/controllers/uptime_controller_spec.rb`

### Modified Files
- `config/routes.rb` — add uptime resources
- `config/initializers/sidekiq_cron.rb` — add scheduler + rollup + SSL expiry cron entries
- `app/views/layouts/admin.html.erb` — add Uptime to sidebar
- `app/jobs/data_retention_job.rb` — add `uptime_checks` cleanup (direct `account_id` query, no projects join)

---

## No New Dependencies

Everything built with existing stack:
- `Net::HTTP` (stdlib) for HTTP checks
- `Sidekiq` + `sidekiq-cron` for scheduling
- `PostgreSQL` for storage
- `Rails 8 encrypts` for header encryption
- `Tailwind CSS` + `Hotwire/Stimulus` for UI
- Existing Slack/Discord/email notification services for alerts
