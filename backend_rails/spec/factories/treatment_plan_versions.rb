FactoryBot.define do
  factory :treatment_plan_version do
    association :treatment_plan
    version_number { 1 }
    source { "ai_generated" }
    therapist_content { { "goals" => [] } }
    client_content { { "summary" => "" } }
  end
end
