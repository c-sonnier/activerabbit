class AddAutoFixToIssues < ActiveRecord::Migration[8.0]
  def change
    add_column :issues, :auto_fix_status, :string
    add_column :issues, :auto_fix_pr_url, :string
    add_column :issues, :auto_fix_pr_number, :integer
    add_column :issues, :auto_fix_branch, :string
    add_column :issues, :auto_fix_attempted_at, :datetime
    add_column :issues, :auto_fix_merged_at, :datetime
    add_column :issues, :auto_fix_error, :text

    add_index :issues, :auto_fix_status, where: "auto_fix_status IS NOT NULL"
  end
end
