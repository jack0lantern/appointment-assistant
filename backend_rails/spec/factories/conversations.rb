FactoryBot.define do
  factory :conversation do
    association :user
    context_type { "general" }
    status { "active" }

    trait :onboarding do
      context_type { "onboarding" }
    end

    trait :paused do
      status { "paused" }
    end
  end
end
