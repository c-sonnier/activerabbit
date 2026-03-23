FactoryBot.define do
  factory :project do
    association :account
    association :user
    sequence(:name) { |n| "Project #{n}" }
    sequence(:slug) { |n| "project-#{n}" }
    url { "http://example.com" }
    environment { "production" }
    tech_stack { "rails" }
    active { true }
    settings { {} }
  end
end
