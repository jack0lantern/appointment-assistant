FactoryBot.define do
  factory :user do
    email { Faker::Internet.unique.email }
    name { Faker::Name.name }
    role { "client" }
    password { "password123" }

    trait :therapist do
      role { "therapist" }
    end

    trait :client do
      role { "client" }
    end
  end
end
