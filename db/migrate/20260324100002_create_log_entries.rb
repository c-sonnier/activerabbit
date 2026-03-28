class CreateLogEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :log_entries do |t|
      t.bigint :account_id, null: false
      t.bigint :project_id, null: false
      t.integer :level, null: false, default: 2
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
