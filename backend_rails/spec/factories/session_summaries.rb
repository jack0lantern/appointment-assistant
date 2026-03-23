FactoryBot.define do
  factory :session_summary do
    association :session
    therapist_summary { "Therapist notes" }
    client_summary { "Client summary" }
    key_themes { ["theme1", "theme2"] }
  end
end
