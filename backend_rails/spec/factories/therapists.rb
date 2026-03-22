FactoryBot.define do
  factory :therapist do
    association :user, :therapist
    license_type { "LCSW" }
    specialties { ["anxiety", "depression"] }
    preferences { {} }
    slug { Faker::Internet.unique.slug(glue: "-") }
  end
end
