require 'rails_helper'

RSpec.describe Uptime::AlertJob, type: :job do
  let(:account) { @test_account }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user, tech_stack: "ruby") }
  let(:monitor) do
    ActsAsTenant.with_tenant(account) do
      create(:uptime_monitor, project: project, name: "Prod API",
             url: "https://api.example.com", status: "down")
    end
  end

  before do
    project.update!(settings: {
      "notifications" => { "enabled" => true, "channels" => { "email" => true } }
    })
    stub_request(:post, "https://api.resend.com/emails")
      .to_return(status: 200, body: '{"id": "test"}', headers: { 'Content-Type' => 'application/json' })
    allow(Sidekiq).to receive(:redis).and_yield(double(set: true))
  end

  describe "#perform" do
    it "sends a down alert email" do
      expect {
        described_class.new.perform(monitor.id, "down", { "consecutive_failures" => 3 })
      }.not_to raise_error
    end

    it "sends a recovery alert" do
      expect {
        described_class.new.perform(monitor.id, "up", { "previous_status" => "down" })
      }.not_to raise_error
    end

    it "skips if monitor not found" do
      expect {
        described_class.new.perform(-1, "down", {})
      }.not_to raise_error
    end

    it "rate-limits duplicate alerts via Redis" do
      allow(Sidekiq).to receive(:redis).and_yield(double(set: false))
      expect(AlertMailer).not_to receive(:send_alert)
      described_class.new.perform(monitor.id, "down", {})
    end
  end
end
