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
