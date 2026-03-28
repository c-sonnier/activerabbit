# frozen_string_literal: true

class AddSlugAndRunStartedAtToCheckIns < ActiveRecord::Migration[8.0]
  def change
    add_column :check_ins, :slug, :string
    add_column :check_ins, :run_started_at, :datetime

    add_index :check_ins, [:project_id, :slug], unique: true
  end
end
