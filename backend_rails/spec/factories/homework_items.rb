FactoryBot.define do
  factory :homework_item do
    association :treatment_plan_version
    association :client
    description { "Practice breathing exercises daily" }
    completed { false }
  end
end
