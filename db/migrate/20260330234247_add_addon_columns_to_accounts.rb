class AddAddonColumnsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :addon_uptime_monitors, :integer, default: 0, null: false
    add_column :accounts, :addon_extra_errors, :integer, default: 0, null: false
    add_column :accounts, :addon_session_replays, :integer, default: 0, null: false
  end
end
