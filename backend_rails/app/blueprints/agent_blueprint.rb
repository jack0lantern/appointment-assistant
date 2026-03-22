class AgentBlueprint < Blueprinter::Base
  # Matches AgentChatResponse from Python schemas/agent.py

  view :chat_response do
    field :message
    field :conversation_id
    field :suggested_actions
    field :follow_up_questions
    field :safety
    field :context_type
  end
end
