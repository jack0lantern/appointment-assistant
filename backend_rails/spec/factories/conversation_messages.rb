FactoryBot.define do
  factory :conversation_message do
    association :conversation
    role { "user" }
    content { "Hello, I need help" }
  end
end
