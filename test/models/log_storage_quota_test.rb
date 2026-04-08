# frozen_string_literal: true

require "test_helper"

class LogStorageQuotaTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
  end

  test "log_quota_exceeded? is false when under byte limit" do
    @account.update!(cached_log_bytes_used: ResourceQuotas::LOG_BYTES_QUOTA - 1)

    assert_not @account.log_quota_exceeded?
  ensure
    @account.update!(cached_log_bytes_used: 0)
  end

  test "log_quota_exceeded? is true at or above byte limit" do
    @account.update!(cached_log_bytes_used: ResourceQuotas::LOG_BYTES_QUOTA)

    assert @account.log_quota_exceeded?
  ensure
    @account.update!(cached_log_bytes_used: 0)
  end

  test "log_bytes_used reads cached column" do
    @account.update!(cached_log_bytes_used: 123)

    assert_equal 123, @account.log_bytes_used
  ensure
    @account.update!(cached_log_bytes_used: 0)
  end

  test "log_bytes_quota matches plan constant" do
    assert_equal ResourceQuotas::LOG_BYTES_QUOTA, @account.log_bytes_quota
  end
end
