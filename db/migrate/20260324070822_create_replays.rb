class CreateReplays < ActiveRecord::Migration[8.0]
  def change
    create_table :replays do |t|
      t.bigint :account_id, null: false
      t.bigint :project_id, null: false
      t.bigint :issue_id
      t.uuid :replay_id, null: false
      t.uuid :session_id, null: false
      t.integer :segment_index, default: 0
      t.string :trigger_type
      t.string :trigger_error_class
      t.string :trigger_error_short
      t.string :status, null: false, default: "pending"
      t.string :storage_key
      t.integer :compressed_size
      t.integer :uncompressed_size
      t.integer :event_count
      t.datetime :started_at, null: false
      t.datetime :captured_at
      t.datetime :uploaded_at
      t.integer :duration_ms, null: false
      t.integer :trigger_offset_ms
      t.text :url
      t.text :user_agent
      t.integer :viewport_width
      t.integer :viewport_height
      t.string :environment
      t.string :release_version
      t.string :sdk_version
      t.string :rrweb_version
      t.integer :schema_version, default: 1
      t.string :checksum_sha256
      t.datetime :retention_until
      t.timestamps
    end

    add_index :replays, :replay_id, unique: true
    add_index :replays, [:account_id, :project_id, :created_at], name: "idx_replays_account_project_created"
    add_index :replays, :session_id
    add_index :replays, :issue_id
    add_index :replays, [:status, :retention_until], name: "idx_replays_status_retention"
  end
end
