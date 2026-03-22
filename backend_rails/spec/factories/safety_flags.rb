FactoryBot.define do
  factory :safety_flag do
    association :session
    flag_type { "suicidal_ideation" }
    severity { "high" }
    description { "Crisis language detected" }
    transcript_excerpt { "I don't want to be here anymore" }
    source { "regex" }
    category { "safety_risk" }
  end
end
