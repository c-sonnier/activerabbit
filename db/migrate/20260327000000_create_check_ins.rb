class CreateCheckIns < ActiveRecord::Migration[8.0]
  def change
    create_table :check_ins do |t|
      t.references :project, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :identifier, null: false
      t.string :kind, default: "cron", null: false
      t.string :schedule_cron
      t.integer :max_run_time_seconds
      t.integer :heartbeat_interval_seconds
      t.string :timezone, default: "UTC"
      t.text :description
      t.boolean :enabled, default: true, null: false
      t.datetime :last_seen_at
      t.string :last_status, default: "success"
      t.datetime :last_alerted_at
      t.timestamps
    end

    add_index :check_ins, [:account_id, :last_status]
    add_index :check_ins, [:project_id, :identifier], unique: true
  end
end
