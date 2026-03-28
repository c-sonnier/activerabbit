class AddLogQuotaToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :cached_log_entries_used, :integer, default: 0
  end
end
