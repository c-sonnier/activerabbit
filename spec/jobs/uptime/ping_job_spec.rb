require 'rails_helper'

RSpec.describe Uptime::PingJob, type: :job do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user, tech_stack: "ruby") }
  let(:monitor) do
    ActsAsTenant.with_tenant(account) do
      create(:uptime_monitor, project: project, status: "pending",
             url: "https://example.com/health", timeout_seconds: 5)
    end
  end

  before do
    allow(Sidekiq).to receive(:redis).and_yield(double(set: true, del: true))
  end

  describe "#perform" do
    context "when URL returns 200" do
      before do
        stub_request(:get, "https://example.com/health")
          .to_return(status: 200, body: "OK", headers: {})
      end

      it "creates a successful Uptime::Check" do
        expect {
          described_class.new.perform(monitor.id)
        }.to change { Uptime::Check.count }.by(1)

        check = Uptime::Check.last
        expect(check.success).to be true
        expect(check.status_code).to eq(200)
      end

      it "updates monitor status to up" do
        described_class.new.perform(monitor.id)
        monitor.reload
        expect(monitor.status).to eq("up")
        expect(monitor.consecutive_failures).to eq(0)
        expect(monitor.last_checked_at).to be_present
      end
    end

    context "when URL returns 500" do
      before do
        stub_request(:get, "https://example.com/health")
          .to_return(status: 500, body: "Error")
      end

      it "creates a failed check" do
        described_class.new.perform(monitor.id)
        check = Uptime::Check.last
        expect(check.success).to be false
        expect(check.status_code).to eq(500)
      end

      it "increments consecutive_failures" do
        described_class.new.perform(monitor.id)
        expect(monitor.reload.consecutive_failures).to eq(1)
      end
    end

    context "when URL times out" do
      before do
        stub_request(:get, "https://example.com/health").to_timeout
      end

      it "creates a failed check with error message" do
        described_class.new.perform(monitor.id)
        check = Uptime::Check.last
        expect(check.success).to be false
        expect(check.error_message).to be_present
      end
    end

    context "when consecutive failures reach alert_threshold" do
      before do
        monitor.update!(consecutive_failures: 2, status: "up", alert_threshold: 3)
        stub_request(:get, "https://example.com/health")
          .to_return(status: 500, body: "Error")
      end

      it "enqueues Uptime::AlertJob on status transition" do
        expect(Uptime::AlertJob).to receive(:perform_async).with(monitor.id, "down", anything)
        described_class.new.perform(monitor.id)
      end
    end

    context "when recovering from down to up" do
      before do
        monitor.update!(consecutive_failures: 5, status: "down")
        stub_request(:get, "https://example.com/health")
          .to_return(status: 200, body: "OK")
      end

      it "enqueues recovery alert" do
        expect(Uptime::AlertJob).to receive(:perform_async).with(monitor.id, "up", anything)
        described_class.new.perform(monitor.id)
      end
    end
  end
end
