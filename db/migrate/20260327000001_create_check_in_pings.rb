class CreateCheckInPings < ActiveRecord::Migration[8.0]
  def change
    create_table :check_in_pings do |t|
      t.references :check_in, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :status, default: "success", null: false
      t.integer :response_time_ms
      t.string :source_ip
      t.datetime :pinged_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :check_in_pings, [:check_in_id, :pinged_at]
    add_index :check_in_pings, [:check_in_id, :status]
  end
end
