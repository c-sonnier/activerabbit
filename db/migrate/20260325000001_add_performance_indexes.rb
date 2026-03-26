class AddPerformanceIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Trigram index for ILIKE searches on log_entries.message
    enable_extension "pg_trgm"
    add_index :log_entries, :message, using: :gin, opclass: :gin_trgm_ops,
              name: "index_log_entries_on_message_trgm", algorithm: :concurrently

    # Composite index for replay filtering by environment
    add_index :replays, [:project_id, :status, :environment, :created_at],
              name: "idx_replays_project_status_env_created", algorithm: :concurrently
  end
end
