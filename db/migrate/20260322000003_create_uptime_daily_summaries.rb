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
