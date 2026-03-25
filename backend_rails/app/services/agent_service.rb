# frozen_string_literal: true

# Core AI chat agent orchestrator.
# Pipeline: input_safety -> classify_intent -> onboarding_redirect -> redact ->
#           build_context -> call_llm_with_tools -> response_safety -> respond
class AgentService
  MAX_TOOL_ROUNDS = 5

  DISCLAIMER = "\n\n---\n*This is an AI assistant and does not provide medical advice, " \
    "diagnoses, or treatment recommendations. Always consult a qualified " \
    "healthcare provider for medical questions.*"

  CRISIS_RESPONSE = "I hear you, and I want you to know that you're not alone. What you're feeling matters.\n\n" \
    "Please reach out for immediate support:\n" \
    "- **988 Suicide & Crisis Lifeline**: Call or text **988** (available 24/7)\n" \
    "- **Crisis Text Line**: Text **HOME** to **741741**\n" \
    "- **Emergency**: Call **911** or go to your nearest emergency room\n\n" \
    "A trained counselor is ready to help right now. Would you like help finding " \
    "additional resources or scheduling an appointment with your therapist?"

  PAUSED_RESPONSE = "Your conversation is currently on hold. A care coordinator will follow up with you shortly. " \
    "If you need immediate help, please call 988 or go to your nearest emergency room."

  # @param llm_service [LlmService] injectable for testing
  def initialize(llm_service: nil)
    @llm_service = llm_service || LlmService.new
    @redactor = RedactionService.new
    @input_safety = InputSafetyService.new
    @response_safety = ResponseSafetyService.new
  end

  # Full orchestration pipeline.
  #
  # @param message [String] raw user message
  # @param user [User] authenticated user
  # @param conversation_id [String, nil]
  # @param context_type [String] one of IntentClassifier::CONTEXT_TYPES
  # @param page_context [Hash, nil]
  # @return [Hash] AgentChatResponse-shaped hash
  def process_message(message:, user:, conversation_id: nil, context_type: "general", page_context: nil)
    auth = build_auth_context(user)

    # 1. Find or create conversation
    conversation = find_or_create_conversation(user: user, conversation_id: conversation_id, context_type: context_type)
    conversation_id = conversation.uuid

    # 1b. Block messages for paused conversations
    if conversation.paused?
      save_message(conversation: conversation, role: "user", content: message)
      holding_text = PAUSED_RESPONSE + DISCLAIMER
      save_message(conversation: conversation, role: "assistant", content: holding_text)
      return {
        message: holding_text,
        conversation_id: conversation_id,
        suggested_actions: [],
        follow_up_questions: [],
        safety: { flagged: false, flag_type: nil, escalated: false },
        context_type: conversation.context_type,
        therapist_results: nil,
        onboarding_state: build_onboarding_state(conversation, conversation.context_type)
      }
    end

    # 2. Input safety check — crisis short-circuit
    safety_result = @input_safety.check(message)

    # Persist risk_level on onboarding progress each turn and track accumulated risk
    if safety_result[:flagged]
      progress = conversation.onboarding
      progress.risk_level = safety_result[:flag_type]

      if safety_result[:flag_type] == "medium"
        progress.medium_risk_count = (progress.medium_risk_count || 0) + 1
      else
        progress.medium_risk_count = 0
      end

      conversation.save_onboarding!(progress)

      # Check accumulated medium-risk turns for auto-escalation
      if safety_result[:flag_type] == "medium"
        escalated = EscalationService.check_accumulated_risk(conversation: conversation)
        if escalated
          save_message(conversation: conversation, role: "user", content: message)
          holding_text = PAUSED_RESPONSE + DISCLAIMER
          save_message(conversation: conversation, role: "assistant", content: holding_text)
          return {
            message: holding_text,
            conversation_id: conversation_id,
            suggested_actions: [],
            follow_up_questions: [],
            safety: { flagged: true, flag_type: "medium", escalated: true },
            context_type: conversation.context_type,
            therapist_results: nil,
            onboarding_state: build_onboarding_state(conversation, conversation.context_type)
          }
        end
      end
    else
      # Low/no risk — reset medium risk counter
      progress = conversation.onboarding
      progress.medium_risk_count = 0
      conversation.save_onboarding!(progress)
    end

    if safety_result[:escalated]
      save_message(conversation: conversation, role: "user", content: message)
      crisis_text = CRISIS_RESPONSE + DISCLAIMER
      save_message(conversation: conversation, role: "assistant", content: crisis_text)
      return {
        message: crisis_text,
        conversation_id: conversation_id,
        suggested_actions: [
          { label: "Schedule urgent session", action_type: "message", payload: "I need to see my therapist soon" },
          { label: "More resources", action_type: "message", payload: "Can you share more crisis resources?" }
        ],
        follow_up_questions: [],
        safety: { flagged: true, flag_type: "crisis", escalated: true },
        context_type: "emotional_support",
        therapist_results: nil,
        onboarding_state: build_onboarding_state(conversation, "emotional_support")
      }
    end

    # 3. Classify intent (may override provided context_type)
    classified = IntentClassifier.classify(message)
    effective_context = classified != "general" ? classified : context_type

    # 4. Onboarding routing: use OnboardingRouter for onboarding context or new users
    redirected_from_scheduling = false
    onboarding_state = nil

    if effective_context == "onboarding" || (effective_context == "scheduling" && auth.role == "client")
      routing = OnboardingRouter.route(user: user, conversation: conversation)
      onboarding_state = routing[:onboarding_progress]

      if effective_context == "scheduling" && routing[:context_type] == "onboarding"
        redirected_from_scheduling = true
      end

      effective_context = routing[:context_type]
    end

    # 5. Redact PII (load prior turn mappings so we can restore tokens from history)
    @redactor.load_mappings(conversation.redaction_mappings || {})
    redaction_result = @redactor.redact(message)
    redacted_message = redaction_result.redacted_text

    # 6. Load conversation history (truncate oldest turns to avoid LLM context overflow)
    history = ChatHistoryTruncator.truncate(load_history(conversation))

    # 7. Build context (system prompt + messages)
    ctx = ContextBuilder.build(
      context_type: effective_context,
      redacted_message: redacted_message,
      history: history,
      redirected: redirected_from_scheduling,
      onboarding_state: onboarding_state
    )

    system_prompt = ctx[:system_prompt]

    # Append therapist hint for onboarded client with assigned therapist
    if !redirected_from_scheduling &&
        effective_context == "scheduling" &&
        auth.role == "client" &&
        auth.therapist_id.present?
      system_prompt += "\n\nIMPORTANT: The user is a client with an assigned therapist. " \
        "Use therapist_id #{auth.therapist_id} for get_available_slots and book_appointment. " \
        "Do NOT ask which therapist they want to see — proceed directly to showing available times."
    end

    # Therapist scheduling: require patient name before proceeding
    if effective_context == "scheduling" && auth.role == "therapist"
      system_prompt += "\n\nIMPORTANT: You are assisting a therapist who wants to manage appointments " \
        "on behalf of a client. Before calling any scheduling tools (get_available_slots, book_appointment, " \
        "list_appointments, cancel_appointment), you MUST first ask which patient this is for. " \
        "Call search_clients with the patient name to resolve the client_id. " \
        "Use therapist_id #{auth.therapist_id} for get_available_slots and book_appointment. " \
        "Pass the resolved client_id to book_appointment, list_appointments, and cancel_appointment."
    end

    # 8. Call LLM with tool loop
    llm_response = {}
    begin
      llm_response = call_llm_with_tools(
        system_prompt: system_prompt,
        messages: ctx[:messages],
        auth: auth
      )
    rescue StandardError => e
      Rails.logger.error("LLM call failed: #{e.message}")
      llm_response = { text: "I'm sorry, I'm having trouble processing your request right now. " \
        "Please try again in a moment, or contact support if this continues." }
    end

    response_text = llm_response[:text] || llm_response["text"] || ""
    therapist_results = llm_response[:therapist_results] || llm_response["therapist_results"]
    appointment_results = llm_response[:appointment_results] || llm_response["appointment_results"]
    llm_suggested_actions = llm_response[:suggested_actions] || llm_response["suggested_actions"]
    executed_tools = llm_response[:executed_tools] || llm_response["executed_tools"] || []

    # 9. Response safety check
    resp_safety = @response_safety.check(response_text)
    if resp_safety[:flagged]
      Rails.logger.warn("Agent response flagged for safety: #{resp_safety[:flag_type]}")
      response_text = resp_safety[:replacement]
    end

    # 10. Append disclaimer (skip if LLM already included equivalent text)
    response_text += DISCLAIMER unless response_text.include?("does not provide medical advice")

    # 11. Restore PII tokens in response so user sees their actual email/name instead of [EMAIL_1] etc
    response_text = @redactor.restore(response_text)

    # 12. Persist messages
    save_message(conversation: conversation, role: "user", content: redacted_message)
    save_message(conversation: conversation, role: "assistant", content: response_text)

    # Persist redaction mappings so future turns can restore tokens from history
    merged = (conversation.redaction_mappings || {}).merge(@redactor.export_mappings)
    conversation.update_column(:redaction_mappings, merged) if merged.present?

    # Update conversation context type if it changed
    conversation.update!(context_type: effective_context) if conversation.context_type != effective_context

    # Reload onboarding progress (may have been updated by tools like confirm_therapist, upload_document)
    conversation.reload
    onboarding_progress = build_onboarding_state(conversation, effective_context)

    # 13. Build suggested actions — fallback priority:
    #   1. LLM-provided (via set_suggested_actions tool)
    #   2. Tool-aware (based on which tools actually executed this turn)
    #   3. Flow-graph step-appropriate defaults (static per context/step)
    suggested = if llm_suggested_actions.present?
      llm_suggested_actions
    else
      tool_suggestions = ContextBuilder.tool_aware_suggestions(executed_tools)
      actions = tool_suggestions || ContextBuilder.suggested_actions(effective_context, onboarding_progress)
      actions.map do |action|
        { label: action[:label], action_type: "message", payload: action[:payload] }
      end
    end

    if redirected_from_scheduling
      suggested << {
        label: "I'm ready to schedule",
        action_type: "message",
        payload: "I've completed onboarding, I'd like to schedule an appointment"
      }
    end

    {
      message: response_text,
      conversation_id: conversation_id,
      suggested_actions: suggested,
      follow_up_questions: [],
      safety: { flagged: false, flag_type: nil, escalated: false },
      context_type: effective_context,
      therapist_results: therapist_results,
      appointment_results: appointment_results,
      onboarding_state: onboarding_progress
    }
  end

  private

  # Build a ToolAuthContext from an authenticated user.
  def build_auth_context(user)
    client_id = user.client_profile&.id
    therapist_id = user.therapist_profile&.id
    therapist_id ||= user.client_profile&.therapist_id if therapist_id.nil?

    AgentTools::ToolAuthContext.new(
      user_id: user.id,
      role: user.role,
      client_id: client_id,
      therapist_id: therapist_id
    )
  end

  # Find an existing conversation or create a new one.
  def find_or_create_conversation(user:, conversation_id:, context_type:)
    if conversation_id.present?
      conversation = user.conversations.find_by(uuid: conversation_id)
      return conversation if conversation
    end

    user.conversations.create!(context_type: context_type, status: "active")
  end

  # Load conversation history as [{role:, content:}].
  def load_history(conversation)
    conversation.messages.order(:created_at).map do |msg|
      { role: msg.role, content: msg.content }
    end
  end

  # Persist a single message to the conversation.
  def save_message(conversation:, role:, content:)
    conversation.messages.create!(role: role, content: content)
  end

  # Build frontend OnboardingState from conversation. Only for onboarding (new patients).
  def build_onboarding_state(conversation, effective_context)
    return nil unless effective_context == "onboarding"

    progress = conversation.onboarding
    docs_verified = progress.docs_verified || false
    therapist_selected = progress.selected_therapist_id.present?

    step = if progress.appointment_id.present?
      "complete"
    elsif progress.selected_therapist_id.present?
      "schedule"
    elsif docs_verified
      "therapist"
    elsif progress.has_completed_intake
      "documents"
    else
      "intake"
    end

    { step: step, docs_verified: docs_verified, therapist_selected: therapist_selected }
  end

  # Multi-turn tool-calling loop.
  # Calls LLM -> if tool_use blocks, execute tools -> feed results back -> repeat.
  # Max MAX_TOOL_ROUNDS iterations.
  # Returns { text:, therapist_results:, suggested_actions:, executed_tools: }
  # suggested_actions populated when LLM calls set_suggested_actions.
  # executed_tools tracks which tools ran this turn for fallback suggestion logic.
  def call_llm_with_tools(system_prompt:, messages:, auth:)
    text_parts = []
    last_therapist_results = nil
    last_appointment_results = nil
    llm_suggested_actions = nil
    executed_tools = []

    MAX_TOOL_ROUNDS.times do |round|
      response = @llm_service.call(
        system_prompt: system_prompt,
        messages: messages,
        tools: AgentTools::TOOL_DEFINITIONS
      )

      content_blocks = response["content"] || []
      text_parts = []
      tool_uses = []

      content_blocks.each do |block|
        case block["type"]
        when "text"
          text_parts << block["text"]
        when "tool_use"
          tool_uses << {
            "id" => block["id"],
            "name" => block["name"],
            "input" => block["input"]
          }
        end
      end

      # No tool calls — return the text, therapist/appointment results, and any captured suggested actions
      if tool_uses.empty?
        return {
          text: text_parts.join("\n"),
          therapist_results: last_therapist_results,
          appointment_results: last_appointment_results,
          suggested_actions: llm_suggested_actions,
          executed_tools: executed_tools
        }
      end

      # If the only tool is set_suggested_actions (and we have text), capture and return early
      # so we don't feed the result back — the buttons should match the options in the response
      only_suggested_actions = tool_uses.all? { |t| t["name"] == "set_suggested_actions" }
      if only_suggested_actions && text_parts.any?
        tool_uses.each do |t|
          next unless t["name"] == "set_suggested_actions"

          actions = t["input"]["actions"] || t["input"][:actions] || []
          llm_suggested_actions = actions.filter_map do |a|
            label = a["label"] || a[:label]
            payload = a["payload"] || a[:payload]
            next if label.blank? || payload.blank?

            { label: label.to_s, action_type: "message", payload: payload.to_s }
          end
          break
        end
        return {
          text: text_parts.join("\n"),
          therapist_results: last_therapist_results,
          appointment_results: last_appointment_results,
          suggested_actions: llm_suggested_actions,
          executed_tools: executed_tools
        }
      end

      # Execute each tool and collect results
      tool_results = tool_uses.map do |tool_call|
        Rails.logger.info("Executing tool: #{tool_call['name']} (round #{round + 1})")
        executed_tools << tool_call["name"]
        result = AgentTools.execute_tool(
          name: tool_call["name"],
          input: tool_call["input"] || {},
          auth_context: auth
        )
        # Capture therapist search results for frontend rich rendering
        therapists = result[:therapists] || result["therapists"]
        if tool_call["name"] == "search_therapists" && result.is_a?(Hash) && therapists.present?
          last_therapist_results = therapists
        end
        # Capture appointment list for cancel flow — frontend renders as selectable cards
        appointments = result[:appointments] || result["appointments"]
        if tool_call["name"] == "list_appointments" && result.is_a?(Hash) && appointments.present?
          last_appointment_results = appointments
        end
        # Capture suggested actions from set_suggested_actions tool
        if tool_call["name"] == "set_suggested_actions"
          input = tool_call["input"] || {}
          actions = input["actions"] || input[:actions] || []
          llm_suggested_actions = actions.filter_map do |a|
            label = a["label"] || a[:label]
            payload = a["payload"] || a[:payload]
            next if label.blank? || payload.blank?

            { label: label.to_s, action_type: "message", payload: payload.to_s }
          end
        end
        {
          type: "tool_result",
          tool_use_id: tool_call["id"],
          content: result.to_json
        }
      end

      # Build assistant message with full content blocks
      assistant_content = content_blocks.map do |block|
        case block["type"]
        when "text"
          { type: "text", text: block["text"] }
        when "tool_use"
          { type: "tool_use", id: block["id"], name: block["name"], input: block["input"] }
        end
      end.compact

      messages << { role: "assistant", content: assistant_content }
      messages << { role: "user", content: tool_results }
    end

    # Exhausted all rounds
    text = text_parts.any? ? text_parts.join("\n") : "I'm sorry, I wasn't able to complete that action. Please try again."
    {
      text: text,
      therapist_results: last_therapist_results,
      appointment_results: last_appointment_results,
      suggested_actions: llm_suggested_actions,
      executed_tools: executed_tools
    }
  end
end
