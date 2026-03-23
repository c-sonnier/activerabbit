FactoryBot.define do
  factory :uptime_check do
    association :account
    association :uptime_monitor
    status_code { 200 }
    response_time_ms { 150 }
    success { true }
    region { "us-east" }
    dns_time_ms { 10 }
    connect_time_ms { 20 }
    tls_time_ms { 30 }
    ttfb_ms { 90 }
  end
end
