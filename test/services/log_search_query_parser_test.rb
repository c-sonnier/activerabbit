require "test_helper"

class LogSearchQueryParserTest < ActiveSupport::TestCase
  test "parses level filter" do
    result = LogSearchQueryParser.parse("level:error")
    assert_equal :error, result[:level]
  end

  test "parses source filter" do
    result = LogSearchQueryParser.parse("source:StripeService")
    assert_equal "StripeService", result[:source]
  end

  test "parses environment filter" do
    result = LogSearchQueryParser.parse("env:production")
    assert_equal "production", result[:environment]
  end

  test "parses trace_id filter" do
    result = LogSearchQueryParser.parse("trace:tr_abc123")
    assert_equal "tr_abc123", result[:trace_id]
  end

  test "parses free text as message filter" do
    result = LogSearchQueryParser.parse("payment failed")
    assert_equal "payment failed", result[:message]
  end

  test "parses mixed filters and free text" do
    result = LogSearchQueryParser.parse("level:error payment failed")
    assert_equal :error, result[:level]
    assert_equal "payment failed", result[:message]
  end

  test "parses unknown keys as param filters" do
    result = LogSearchQueryParser.parse("customer_id:cus_123")
    assert_equal({ "customer_id" => "cus_123" }, result[:params])
  end

  test "handles empty query" do
    assert_equal({}, LogSearchQueryParser.parse(""))
    assert_equal({}, LogSearchQueryParser.parse(nil))
  end

  test "handles quoted values" do
    result = LogSearchQueryParser.parse('source:"Stripe Service"')
    assert_equal "Stripe Service", result[:source]
  end
end
