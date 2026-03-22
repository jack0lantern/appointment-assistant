FactoryBot.define do
  factory :client do
    association :user, :client
    association :therapist
    name { Faker::Name.name }
  end
end
