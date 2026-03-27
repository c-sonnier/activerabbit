class AddSourceToEventsAndIssues < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :source, :string, default: "backend", null: false
    add_column :issues, :source, :string, default: "backend", null: false

    add_index :events, :source
    add_index :issues, :source
  end
end
