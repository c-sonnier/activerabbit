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
