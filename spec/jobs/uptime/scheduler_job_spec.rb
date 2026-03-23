require 'rails_helper'

RSpec.describe Uptime::SchedulerJob, type: :job do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user, tech_stack: "ruby") }

  describe "#perform" do
    it "enqueues Uptime::PingJob for monitors due for a check" do
      ActsAsTenant.with_tenant(account) do
        due = create(:uptime_monitor, project: project, status: "up",
                     last_checked_at: 10.minutes.ago, interval_seconds: 300)
        not_due = create(:uptime_monitor, project: project, status: "up",
                         last_checked_at: 1.minute.ago, interval_seconds: 300)
        paused = create(:uptime_monitor, project: project, status: "paused")

        expect(Uptime::PingJob).to receive(:perform_async).with(due.id).once
        expect(Uptime::PingJob).not_to receive(:perform_async).with(not_due.id)
        expect(Uptime::PingJob).not_to receive(:perform_async).with(paused.id)

        described_class.new.perform
      end
    end

    it "enqueues monitors that have never been checked" do
      ActsAsTenant.with_tenant(account) do
        never_checked = create(:uptime_monitor, project: project, status: "pending", last_checked_at: nil)
        expect(Uptime::PingJob).to receive(:perform_async).with(never_checked.id)
        described_class.new.perform
      end
    end
  end
end
