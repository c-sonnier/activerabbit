require 'rails_helper'

RSpec.describe Uptime::Monitor, type: :model do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user, tech_stack: "ruby") }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_presence_of(:interval_seconds) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[up down degraded paused pending]) }
    it { is_expected.to validate_inclusion_of(:http_method).in_array(%w[GET HEAD POST]) }
    it { is_expected.to validate_numericality_of(:interval_seconds).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:timeout_seconds).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:expected_status_code).is_greater_than(0) }
  end

  describe 'url validation' do
    it 'rejects non-http URLs' do
      monitor = build(:uptime_monitor, project: project, url: 'ftp://example.com')
      expect(monitor).not_to be_valid
      expect(monitor.errors[:url]).to include('must start with http:// or https://')
    end

    it 'accepts https URLs' do
      monitor = build(:uptime_monitor, project: project, url: 'https://example.com/health')
      expect(monitor).to be_valid
    end
  end

  describe 'scopes' do
    it '.active returns non-paused monitors' do
      ActsAsTenant.with_tenant(account) do
        active = create(:uptime_monitor, project: project, status: 'up')
        paused = create(:uptime_monitor, project: project, status: 'paused')
        expect(Uptime::Monitor.active).to include(active)
        expect(Uptime::Monitor.active).not_to include(paused)
      end
    end

    it '.due_for_check returns monitors needing a check' do
      ActsAsTenant.with_tenant(account) do
        due = create(:uptime_monitor, project: project, status: 'up',
                     last_checked_at: 10.minutes.ago, interval_seconds: 300)
        not_due = create(:uptime_monitor, project: project, status: 'up',
                         last_checked_at: 1.minute.ago, interval_seconds: 300)
        never_checked = create(:uptime_monitor, project: project, status: 'pending',
                               last_checked_at: nil)
        results = Uptime::Monitor.due_for_check
        expect(results).to include(due, never_checked)
        expect(results).not_to include(not_due)
      end
    end
  end

  describe '#pause! / #resume!' do
    it 'toggles status' do
      ActsAsTenant.with_tenant(account) do
        monitor = create(:uptime_monitor, project: project, status: 'up')
        monitor.pause!
        expect(monitor.reload.status).to eq('paused')
        monitor.resume!
        expect(monitor.reload.status).to eq('pending')
      end
    end
  end
end
