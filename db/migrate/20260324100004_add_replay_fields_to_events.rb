class AddReplayFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :replay_id, :uuid
    add_column :events, :session_id, :uuid
    add_index :events, :replay_id
  end
end
