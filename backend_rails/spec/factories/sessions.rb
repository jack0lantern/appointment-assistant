FactoryBot.define do
  factory :session do
    association :therapist
    association :client
    session_date { 1.day.from_now }
    session_number { 1 }
    duration_minutes { 50 }
    status { "completed" }
    session_type { "uploaded" }

    trait :scheduled do
      status { "scheduled" }
      session_type { "live" }
    end
  end
end
