# frozen_string_literal: true

class DataRetentionJob < ApplicationJob
  queue_as :default

  # Default retention for paid plans; free plan uses 5 days (from PLAN_QUOTAS)
  DEFAULT_RETENTION_DAYS = 31
  FREE_PLAN_RETENTION_DAYS = 5
  BATCH_SIZE = 50_000  # Larger batches since we have indexes on occurred_at
  PURGEABLE_TABLES = %w[events performance_events log_entries].freeze

  # Delete events and performance events based on plan-specific retention.
  # Runs daily via Sidekiq Cron.
  #
  # Retention policy:
  #   - Free plan:  5 days  (data older than 5 days is deleted)
  #   - Paid plans: 31 days (data older than 31 days is deleted)
  #
  # Performance notes for large datasets (millions of rows):
  # - Uses raw SQL DELETE with LIMIT for efficiency (avoids Rails subquery)
  # - Batch size of 50K balances speed vs lock duration
  # - Both tables have indexes on occurred_at
  # - Expected: ~2-3 minutes for 6M rows
  def perform
    ActsAsTenant.without_tenant do
      # Phase 1: Delete old data for free-plan accounts (5 days)
      free_account_ids = free_plan_account_ids
      if free_account_ids.any?
        free_cutoff = FREE_PLAN_RETENTION_DAYS.days.ago
        Rails.logger.info "[DataRetention] Free plan cleanup (#{free_account_ids.size} accounts): records older than #{free_cutoff}"

        events_deleted = delete_old_events_for_accounts(free_cutoff, free_account_ids)
        perf_deleted = delete_old_performance_events_for_accounts(free_cutoff, free_account_ids)
        uptime_deleted = delete_old_uptime_checks_for_accounts(free_cutoff, free_account_ids)
        logs_deleted = delete_in_batches_for_accounts("log_entries", free_cutoff, free_account_ids)

        Rails.logger.info "[DataRetention] Free plan completed: deleted #{events_deleted} events, #{perf_deleted} performance events, #{uptime_deleted} uptime checks, #{logs_deleted} log entries"
      end

      # Phase 2: Delete old data for ALL accounts (31 days global max)
      global_cutoff = DEFAULT_RETENTION_DAYS.days.ago
      Rails.logger.info "[DataRetention] Global cleanup: records older than #{global_cutoff}"

      events_deleted = delete_old_events(global_cutoff)
      perf_deleted = delete_old_performance_events(global_cutoff)
      uptime_deleted = delete_old_uptime_checks(global_cutoff)
      logs_deleted = delete_in_batches("log_entries", global_cutoff)

      Rails.logger.info "[DataRetention] Global completed: deleted #{events_deleted} events, #{perf_deleted} performance events, #{uptime_deleted} uptime checks, #{logs_deleted} log entries"
    end
  end

  private

  # Find account IDs on the free plan (no active subscription, trial expired or never started)
  def free_plan_account_ids
    Account.where(current_plan: %w[free developer trial]).where(
      "trial_ends_at IS NULL OR trial_ends_at < ?", Time.current
    ).pluck(:id)
  end

  def delete_old_events(cutoff_date)
    delete_in_batches("events", cutoff_date)
  end

  def delete_old_performance_events(cutoff_date)
    delete_in_batches("performance_events", cutoff_date)
  end

  def delete_old_events_for_accounts(cutoff_date, account_ids)
    delete_in_batches_for_accounts("events", cutoff_date, account_ids)
  end

  def delete_old_performance_events_for_accounts(cutoff_date, account_ids)
    delete_in_batches_for_accounts("performance_events", cutoff_date, account_ids)
  end

  def delete_old_uptime_checks(cutoff_date)
    delete_uptime_in_batches(cutoff_date)
  end

  def delete_old_uptime_checks_for_accounts(cutoff_date, account_ids)
    delete_uptime_in_batches(cutoff_date, account_ids)
  end

  def delete_in_batches(table_name, cutoff_date)
    validate_table_name!(table_name)
    total_deleted = 0
    conn = ActiveRecord::Base.connection
    quoted_table = conn.quote_table_name(table_name)

    loop do
      sql = ActiveRecord::Base.sanitize_sql_array([
        "DELETE FROM #{quoted_table} WHERE ctid IN (SELECT ctid FROM #{quoted_table} WHERE occurred_at < ? LIMIT ?)",
        cutoff_date.utc,
        BATCH_SIZE
      ])

      result = conn.execute(sql)
      deleted_count = result.cmd_tuples
      total_deleted += deleted_count

      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} #{table_name} (total: #{total_deleted})"
      sleep(0.1) if deleted_count == BATCH_SIZE
    end

    total_deleted
  end

  def delete_in_batches_for_accounts(table_name, cutoff_date, account_ids)
    validate_table_name!(table_name)
    total_deleted = 0
    conn = ActiveRecord::Base.connection
    quoted_table = conn.quote_table_name(table_name)

    loop do
      sql = ActiveRecord::Base.sanitize_sql_array([
        "DELETE FROM #{quoted_table} WHERE ctid IN (" \
          "SELECT #{quoted_table}.ctid FROM #{quoted_table} " \
          "INNER JOIN projects ON projects.id = #{quoted_table}.project_id " \
          "WHERE #{quoted_table}.occurred_at < ? " \
          "AND projects.account_id IN (?) " \
          "LIMIT ?" \
        ")",
        cutoff_date.utc,
        account_ids,
        BATCH_SIZE
      ])

      result = conn.execute(sql)
      deleted_count = result.cmd_tuples
      total_deleted += deleted_count

      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} #{table_name} for free accounts (total: #{total_deleted})"
      sleep(0.1) if deleted_count == BATCH_SIZE
    end

    total_deleted
  end

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

  def validate_table_name!(table_name)
    raise ArgumentError, "Unknown table: #{table_name}" unless PURGEABLE_TABLES.include?(table_name)
  end
end
