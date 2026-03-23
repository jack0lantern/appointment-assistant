class ContextBuilder
  BASE_RULES = <<~RULES

    RULES:
    - When you present the user with specific options or follow-up choices (e.g. "what brings you to therapy?" with examples like anxiety, depression, relationship challenges), call the set_suggested_actions tool with those options. The buttons will then match what you offered. Each action needs a short label (button text) and payload (the message sent when tapped). Use 3–5 options.
    - Be warm, concise, and validating.
    - NEVER provide diagnoses, medication advice, prescription recommendations, or clinical recommendations of any kind.
    - NEVER suggest, recommend, or discuss specific medications, supplements, dosages, or treatments. If asked about medication, direct the user to their prescribing provider or therapist.
    - NEVER provide medical advice, including advice about symptoms, conditions, side effects, drug interactions, or whether to start/stop/change any treatment.
    - If the user expresses crisis or self-harm ideation, immediately encourage them to contact 988 Suicide & Crisis Lifeline or go to the nearest ER.
    - Do not ask for or repeat personal identifying information.
    - Keep responses under 3 short paragraphs.
    - Any identifiers in the conversation have been replaced with tokens like [NAME_1] or [EMAIL_1]. Do not attempt to guess real values behind tokens.
    - You have access to tools. Use them when appropriate — e.g., call get_current_datetime before resolving relative dates like 'next Tuesday', call get_available_slots before suggesting times, etc.
    - When booking or cancelling, ALWAYS use the tools rather than just describing the action.
    - After a tool call succeeds, summarize the result naturally for the user.
  RULES

  SYSTEM_PROMPTS = {
    "general" =>
      "You are a supportive, empathetic AI assistant for a mental health " \
      "care platform. You help users with onboarding, scheduling appointments, and " \
      "answering general questions about the platform." + BASE_RULES,

    "onboarding" =>
      "You are a supportive AI assistant helping a new user through the " \
      "onboarding process. Guide them step by step: welcome them, explain what to " \
      "expect, help them understand what information is needed, and make the process " \
      "feel approachable." + BASE_RULES,

    "scheduling" =>
      "You are a supportive AI assistant helping a user schedule, reschedule, or " \
      "cancel a therapy appointment. Help them find suitable times " \
      "and walk them through the process.\n" \
      "When the user asks to schedule, first call get_current_datetime to know today's date, " \
      "then call get_available_slots to find open times. Present the options clearly. " \
      "When the user picks a slot, call book_appointment with the correct slot_id.\n" \
      "When the user asks to cancel an appointment, first call list_appointments to show their " \
      "upcoming appointments. If there are any, the frontend will display them as selectable cards. " \
      "Ask which one they want to cancel — when they tap a card they will send a message like " \
      "'Cancel session X'; use that session_id in cancel_appointment. If there are no appointments, " \
      "tell them so." + BASE_RULES,

    "emotional_support" =>
      "You are a supportive AI assistant. The user appears to be " \
      "experiencing emotional distress. Your role is to:\n" \
      "- Validate their feelings without minimizing.\n" \
      "- Use the get_validation_message tool to provide warm acknowledgment.\n" \
      "- Use get_grounding_exercise if they need a calming technique.\n" \
      "- Use get_psychoeducation for educational content about anxiety, therapy, etc.\n" \
      "- Encourage them to speak with their therapist or a professional." + BASE_RULES,

    "document_upload" =>
      "You are a supportive AI assistant helping a user upload and verify documents " \
      "(insurance cards, ID, intake forms). Guide them through the " \
      "upload process and confirm extracted information." + BASE_RULES
  }.freeze

  # Flow-graph aligned suggested actions by context type.
  # Onboarding step-specific actions override generic onboarding when step is known.
  SUGGESTED_ACTIONS = {
    "general" => [
      { label: "Help me get started", payload: "I'm new and want to get started" },
      { label: "Schedule an appointment", payload: "I'd like to schedule an appointment" }
    ],
    "onboarding" => [
      { label: "Start onboarding", payload: "I'd like to start the onboarding process" },
      { label: "Upload a document", payload: "I want to upload my insurance card" },
      { label: "What do I need?", payload: "What information do I need to provide?" }
    ],
    # Onboarding step-specific: possible next steps per flow graph
    "onboarding_intake" => [
      { label: "Start onboarding", payload: "I'd like to start the onboarding process" },
      { label: "What do I need?", payload: "What information do I need to provide?" }
    ],
    "onboarding_documents" => [
      { label: "Upload insurance card", payload: "I want to upload my insurance card" },
      { label: "Upload ID", payload: "I want to upload my ID" },
      { label: "What documents do I need?", payload: "What documents do I need to provide?" }
    ],
    "onboarding_therapist" => [
      { label: "Yes, help me find a therapist", payload: "Yes, I'd like help finding a therapist" },
      { label: "Tell me about specialties", payload: "What specialties do you have?" },
      { label: "I have a therapist assigned", payload: "I already have a therapist assigned" }
    ],
    "onboarding_schedule" => [
      { label: "Find available times", payload: "What times are available this week?" },
      { label: "Book my appointment", payload: "I'd like to book an appointment" }
    ],
    "onboarding_complete" => [
      { label: "Find available times", payload: "What times are available?" },
      { label: "Reschedule", payload: "I need to reschedule my appointment" }
    ],
    "scheduling" => [
      { label: "Find available times", payload: "What times are available this week?" },
      { label: "Reschedule my appointment", payload: "I need to reschedule my appointment" },
      { label: "Cancel appointment", payload: "I need to cancel my appointment" }
    ],
    "emotional_support" => [
      { label: "Talk to someone now", payload: "I need to talk to someone right now" },
      { label: "Breathing exercise", payload: "Can you guide me through a breathing exercise?" },
      { label: "Schedule a session", payload: "I'd like to schedule a session with my therapist" }
    ],
    "document_upload" => [
      { label: "Upload insurance card", payload: "I want to upload my insurance card" },
      { label: "Upload ID", payload: "I want to upload my ID" },
      { label: "What documents do I need?", payload: "What documents do I need to provide?" }
    ]
  }.freeze

  # Build the system prompt and messages array for the LLM.
  #
  # @param context_type [String] one of IntentClassifier::CONTEXT_TYPES
  # @param redacted_message [String] the user's message after redaction
  # @param history [Array<Hash>] prior conversation turns [{role:, content:}]
  # @param redirected [Boolean] true when scheduling was redirected to onboarding
  # @param onboarding_state [OnboardingProgress, nil] current onboarding progress
  # @return [Hash] {system_prompt:, messages:}
  def self.build(context_type:, redacted_message:, history: [], redirected: false, onboarding_state: nil)
    system_prompt = SYSTEM_PROMPTS.fetch(context_type, SYSTEM_PROMPTS["general"]).dup

    if redirected
      system_prompt << "\n\nIMPORTANT: The user asked to schedule an appointment but has not completed " \
        "onboarding (no client profile). Guide them through onboarding first. Explain " \
        "what information is needed and that once their profile is set up, they can " \
        "schedule. Do not call scheduling tools until they have completed onboarding."
    end

    # Onboarding-specific prompt enrichments
    if onboarding_state && context_type == "onboarding"
      system_prompt << onboarding_prompt_enrichment(onboarding_state)
    end

    messages = history.map { |msg| { role: msg[:role] || msg["role"], content: msg[:content] || msg["content"] } }
    messages << { role: "user", content: redacted_message }

    { system_prompt: system_prompt, messages: messages }
  end

  # Return suggested actions for a given context type.
  # When context is onboarding and onboarding_state is present, returns step-specific
  # "possible next steps" per the flow graph instead of generic onboarding actions.
  #
  # @param context_type [String]
  # @param onboarding_state [Hash, nil] { step:, docs_verified:, therapist_selected: }
  # @return [Array<Hash>]
  def self.suggested_actions(context_type, onboarding_state = nil)
    if context_type == "onboarding" && onboarding_state&.dig(:step).present?
      step_key = "onboarding_#{onboarding_state[:step]}"
      return SUGGESTED_ACTIONS.fetch(step_key, SUGGESTED_ACTIONS["onboarding"])
    end
    SUGGESTED_ACTIONS.fetch(context_type, SUGGESTED_ACTIONS["general"])
  end

  # Generate onboarding-specific prompt additions based on progress state.
  #
  # @param progress [OnboardingProgress]
  # @return [String]
  def self.onboarding_prompt_enrichment(progress)
    parts = []

    if progress.is_new_user
      parts << "\n\nINTAKE CONTEXT: This is a brand-new user who has not completed intake. " \
        "Welcome them warmly. Collect their basic information (name, reason for seeking therapy, " \
        "insurance details). Make the process feel simple and non-intimidating."
    end

    if progress.assigned_therapist_id
      parts << "\n\nTHERAPIST ASSIGNED: This user has a pre-assigned therapist (ID: #{progress.assigned_therapist_id}). " \
        "Let them know they already have a therapist assigned and can proceed to scheduling " \
        "once onboarding is complete."
    end

    if !progress.is_new_user && progress.assigned_therapist_id.nil? && progress.selected_therapist_id.nil?
      parts << "\n\nTHERAPIST SEARCH NEEDED: This returning user does not yet have a therapist. " \
        "Help them search for and select a therapist. Ask about their preferences " \
        "(specialties, availability, insurance) to find a good match."
    end

    parts.join
  end

  private_class_method :onboarding_prompt_enrichment
end
