class ConversationBlueprint < Blueprinter::Base
  identifier :id

  fields :uuid, :context_type, :status, :title, :created_at

  view :with_messages do
    association :messages, blueprint: ConversationMessageBlueprint
  end
end
