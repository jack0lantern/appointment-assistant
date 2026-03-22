FactoryBot.define do
  factory :treatment_plan do
    association :client
    association :therapist
    status { "draft" }
  end
end
