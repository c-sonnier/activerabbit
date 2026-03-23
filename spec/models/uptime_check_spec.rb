require 'rails_helper'

RSpec.describe UptimeCheck, type: :model do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user, tech_stack: "ruby") }
  let(:monitor) { create(:uptime_monitor, project: project) }

  describe 'scopes' do
    it '.successful returns only successful checks' do
      ActsAsTenant.with_tenant(account) do
        ok = create(:uptime_check, uptime_monitor: monitor, success: true)
        fail_check = create(:uptime_check, uptime_monitor: monitor, success: false, status_code: 500)
        expect(UptimeCheck.successful).to include(ok)
        expect(UptimeCheck.successful).not_to include(fail_check)
      end
    end
  end
end
