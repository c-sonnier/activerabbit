FactoryBot.define do
  factory :log_entry do
    association :account
    association :project
    level { 2 } # info
    message { "Processing payment for customer cus_123" }
    environment { "production" }
    occurred_at { 1.hour.ago }

    trait :error do
      level { 4 }
      message { "Stripe::CardError after 2 retries" }
      source { "StripeService" }
      trace_id { "tr_#{SecureRandom.hex(6)}" }
      request_id { "req_#{SecureRandom.hex(6)}" }
    end

    trait :debug do
      level { 1 }
      message { "Debug info" }
    end

    trait :with_params do
      params { { "customer_id" => "cus_123", "amount" => 2999 } }
    end

    trait :old do
      occurred_at { 40.days.ago }
    end
  end
end
