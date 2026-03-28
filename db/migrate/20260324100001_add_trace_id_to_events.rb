class AddTraceIdToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :trace_id, :string unless column_exists?(:events, :trace_id)
    add_column :events, :request_id, :string unless column_exists?(:events, :request_id)
    add_column :performance_events, :trace_id, :string unless column_exists?(:performance_events, :trace_id)

    add_index :events, :trace_id unless index_exists?(:events, :trace_id)
    add_index :events, :request_id unless index_exists?(:events, :request_id)
    add_index :performance_events, :trace_id unless index_exists?(:performance_events, :trace_id)
  end
end
