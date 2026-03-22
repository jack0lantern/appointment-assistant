FactoryBot.define do
  factory :transcript do
    association :session
    content { "Therapist: How are you feeling today?\nClient: I've been struggling with anxiety." }
    source_type { "uploaded" }
    word_count { 12 }
  end
end
