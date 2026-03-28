# frozen_string_literal: true

require "test_helper"

class CheckInPingTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    ActsAsTenant.current_tenant = @account
    @check_in = check_ins(:api_ok)
  end

  test "creates with required attributes" do
    ping = @check_in.pings.create!(
      status: "success",
      pinged_at: Time.current,
      source_ip: "127.0.0.1"
    )
    assert_equal @account.id, ping.account_id
    assert_equal "success", ping.status
  end

  test "invalid without pinged_at" do
    ping = @check_in.pings.build(status: "success", pinged_at: nil)
    refute ping.valid?
    assert ping.errors[:pinged_at].present?
  end
end
