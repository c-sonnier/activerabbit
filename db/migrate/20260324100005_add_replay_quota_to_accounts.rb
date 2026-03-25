class AddReplayQuotaToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :replay_quota, :integer, default: 100
    add_column :accounts, :cached_replays_used, :integer, default: 0
  end
end
