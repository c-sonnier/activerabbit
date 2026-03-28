FactoryBot.define do
  factory :uptime_daily_summary, class: "Uptime::DailySummary" do
    association :account
    association :monitor, factory: :uptime_monitor
    date { Date.current }
    total_checks { 288 }
    successful_checks { 285 }
    uptime_percentage { 98.96 }
    avg_response_time_ms { 150 }
    p95_response_time_ms { 350 }
    p99_response_time_ms { 500 }
    min_response_time_ms { 80 }
    max_response_time_ms { 800 }
    incidents_count { 1 }
  end
end
