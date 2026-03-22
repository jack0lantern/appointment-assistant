class ConversationMessageBlueprint < Blueprinter::Base
  identifier :id

  fields :role, :content, :created_at
end
