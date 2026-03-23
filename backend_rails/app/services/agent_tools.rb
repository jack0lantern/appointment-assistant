class AgentTools
  ToolAuthContext = Struct.new(:user_id, :role, :client_id, :therapist_id, keyword_init: true)

  TOOL_DEFINITIONS = [
    {
      name: "get_current_datetime",
      description:
        "Returns the current date and time in UTC and the user's contextual " \
        "timezone (defaults to US Mountain). Use this when the user mentions " \
        "relative dates like 'next week', 'tomorrow', 'this Thursday', etc. " \
        "so you can resolve them to actual dates.",
      input_schema: {
        type: "object",
        properties: {},
        required: []
      }
    },
    {
      name: "get_available_slots",
      description:
        "Fetches available appointment slots for a therapist over the next 7 days. " \
        "Returns a list of slots with IDs, dates, times, and duration. " \
        "Use this when the user wants to schedule or reschedule an appointment. " \
        "For clients with an assigned therapist, omit therapist_id — the backend uses their assigned therapist.",
      input_schema: {
        type: "object",
        properties: {
          therapist_id: {
            type: "integer",
            description: "The therapist's ID. Omit for clients with an assigned therapist — backend will use it automatically."
          }
        },
        required: []
      }
    },
    {
      name: "book_appointment",
      description:
        "Books an appointment for the user (or the therapist's client in delegation mode). " \
        "You MUST call get_available_slots first to get valid slot IDs. " \
        "Pass the slot_id. For clients with an assigned therapist, omit therapist_id — backend uses it. " \
        "The backend resolves the real client identity from auth.",
      input_schema: {
        type: "object",
        properties: {
          therapist_id: {
            type: "integer",
            description: "The therapist to book with. Omit for clients with an assigned therapist — backend uses it automatically."
          },
          slot_id: {
            type: "string",
            description: "The slot ID from get_available_slots (format: therapist_id:ISO8601, e.g. 5:2026-03-24T19:00:00Z). Pass the exact ID from the list."
          },
          client_id: {
            type: "integer",
            description:
              "Only required when a therapist is booking on behalf of a client. " \
              "Omit when the user is a client (their identity comes from auth)."
          }
        },
        required: %w[slot_id]
      }
    },
    {
      name: "list_appointments",
      description:
        "Lists the user's upcoming scheduled appointments that can be cancelled. " \
        "Call this first when the user wants to cancel an appointment — it shows their " \
        "appointments as selectable cards. The user taps one to choose which to cancel; " \
        "they will then send a message like 'Cancel session X' (X = session_id). Use that in cancel_appointment.",
      input_schema: {
        type: "object",
        properties: {
          client_id: {
            type: "integer",
            description:
              "Only required when a therapist is listing on behalf of a client. " \
              "Omit when the user is a client."
          }
        },
        required: []
      }
    },
    {
      name: "cancel_appointment",
      description:
        "Cancels an existing appointment by session ID. " \
        "The backend validates that the caller owns the session. " \
        "Use the session_id from list_appointments after the user selects which appointment to cancel.",
      input_schema: {
        type: "object",
        properties: {
          session_id: {
            type: "integer",
            description: "The session ID to cancel."
          },
          client_id: {
            type: "integer",
            description:
              "Only required when a therapist is cancelling on behalf of a client. " \
              "Omit when the user is a client."
          }
        },
        required: ["session_id"]
      }
    },
    {
      name: "get_grounding_exercise",
      description:
        "Returns a grounding or breathing exercise to help the user manage " \
        "anxiety or emotional distress. Use this when the user is feeling " \
        "overwhelmed, anxious, or asks for a calming technique.",
      input_schema: {
        type: "object",
        properties: {},
        required: []
      }
    },
    {
      name: "get_psychoeducation",
      description:
        "Returns brief psychoeducation content on a topic. " \
        "Available topics: 'anxiety', 'first_session', 'therapy_general'. " \
        "Use when the user asks about what therapy is like or about a mental health topic.",
      input_schema: {
        type: "object",
        properties: {
          topic: {
            type: "string",
            enum: %w[anxiety first_session therapy_general],
            description: "The psychoeducation topic."
          }
        },
        required: ["topic"]
      }
    },
    {
      name: "get_what_to_expect",
      description:
        "Returns content about what the user can expect for a given stage. " \
        "Available contexts: 'onboarding', 'first_appointment'. " \
        "Use when the user asks what to expect or seems nervous about a step.",
      input_schema: {
        type: "object",
        properties: {
          context: {
            type: "string",
            enum: %w[onboarding first_appointment],
            description: "Which stage to describe."
          }
        },
        required: ["context"]
      }
    },
    {
      name: "get_validation_message",
      description:
        "Returns a warm, validating message. Use this when the user shares " \
        "difficult feelings and needs acknowledgment before anything else.",
      input_schema: {
        type: "object",
        properties: {},
        required: []
      }
    },
    {
      name: "search_therapists",
      description:
        "Search for therapists by name, specialty, or other criteria. " \
        "Returns therapist names (or names with license disambiguation for duplicates).",
      input_schema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Name or partial name to search for." },
          specialty: { type: "string", description: "Specialty to filter by (e.g. 'anxiety', 'depression')." }
        }
      }
    },
    {
      name: "confirm_therapist",
      description:
        "Confirm therapist selection by name after searching. " \
        "Saves the selected therapist to the onboarding conversation.",
      input_schema: {
        type: "object",
        properties: {
          display_label: { type: "string", description: "The therapist name from search results (e.g. 'Dr. Sarah Chen')." }
        },
        required: ["display_label"]
      }
    },
    {
      name: "check_document_status",
      description: "Check if the user has uploaded and verified their documents",
      input_schema: {
        type: "object",
        properties: {}
      }
    },
    {
      name: "upload_document",
      description:
        "Reference a document by its document_ref after the user has uploaded it. " \
        "Returns the redacted preview and status. Use when the user mentions they " \
        "uploaded a document and you need to reference its contents.",
      input_schema: {
        type: "object",
        properties: {
          document_ref: {
            type: "string",
            description: "The document reference ID returned from the upload endpoint."
          }
        },
        required: ["document_ref"]
      }
    },
    {
      name: "set_suggested_actions",
      description:
        "Set the quick-action buttons shown to the user. Call this when you present " \
        "specific options or follow-up choices (e.g. 'what brings you to therapy?' with " \
        "anxiety, depression, relationship challenges). The buttons will match the " \
        "options you offer. Each action needs a short label (button text) and payload " \
        "(the message sent when the user taps it). Use 3–5 options max.",
      input_schema: {
        type: "object",
        properties: {
          actions: {
            type: "array",
            items: {
              type: "object",
              properties: {
                label: { type: "string", description: "Short button text (e.g. 'Anxiety')" },
                payload: { type: "string", description: "Message sent when tapped" }
              },
              required: %w[label payload]
            }
          }
        },
        required: ["actions"]
      }
    }
  ].freeze

  # Execute a tool by name, dispatching to the appropriate service.
  #
  # @param name [String] tool name
  # @param input [Hash] tool input parameters
  # @param auth_context [ToolAuthContext] authenticated user context
  # @return [Hash] result or error hash
  def self.execute_tool(name:, input: {}, auth_context:)
    case name
    when "get_current_datetime"
      exec_get_current_datetime

    when "get_available_slots"
      guard = onboarding_guard(auth_context)
      return guard if guard

      exec_get_available_slots(input, auth_context)

    when "book_appointment"
      guard = onboarding_guard(auth_context)
      return guard if guard

      exec_book_appointment(input, auth_context)

    when "list_appointments"
      exec_list_appointments(input, auth_context)

    when "cancel_appointment"
      exec_cancel_appointment(input, auth_context)

    when "get_grounding_exercise"
      { exercise: EmotionalSupportService.grounding_exercise }

    when "get_psychoeducation"
      topic = input["topic"] || input[:topic] || ""
      content = EmotionalSupportService.psychoeducation(topic)
      content ? { content: content } : { error: "Unknown topic: #{topic}" }

    when "get_what_to_expect"
      context = input["context"] || input[:context] || ""
      content = EmotionalSupportService.what_to_expect(context)
      content ? { content: content } : { error: "Unknown context: #{context}" }

    when "get_validation_message"
      { message: EmotionalSupportService.validation_message }

    when "search_therapists"
      exec_search_therapists(input, auth_context)

    when "confirm_therapist"
      exec_confirm_therapist(input, auth_context)

    when "check_document_status"
      exec_check_document_status(auth_context)

    when "upload_document"
      exec_upload_document(input, auth_context)

    when "set_suggested_actions"
      # Side-effect tool: AgentService captures the input; we just return success
      { success: true }

    else
      { error: "Unknown tool: #{name}" }
    end
  rescue StandardError => e
    Rails.logger.error("Tool #{name} error: #{e.message}")
    { error: e.message }
  end

  class << self
    private

    # Returns an error hash if the client user has not completed onboarding
    # (documents not yet verified). Returns nil when the user may proceed.
    def onboarding_guard(auth_context)
      return nil unless auth_context.role == "client"

      user = User.find_by(id: auth_context.user_id)
      return nil unless user

      # No client profile → must onboard first
      return onboarding_incomplete_error("intake") if auth_context.client_id.nil?

      # Check active onboarding conversation for progress (most recent)
      conversation = user.conversations.where(context_type: "onboarding", status: "active").order(created_at: :desc).first

      # If user is the demo new-patient, always require onboarding
      if user.email == OnboardingRouter::DEMO_NEW_PATIENT_EMAIL
        progress = conversation&.onboarding || OnboardingProgress.new
        return onboarding_incomplete_error(missing_step(progress)) unless progress.docs_verified
      end

      # If there's an active onboarding conversation, enforce step completion
      if conversation
        progress = conversation.onboarding
        unless progress.docs_verified
          return onboarding_incomplete_error(missing_step(progress))
        end
      end

      nil
    end

    def missing_step(progress)
      if !progress.has_completed_intake
        "intake"
      else
        "documents"
      end
    end

    def onboarding_incomplete_error(step)
      messages = {
        "intake" => "You need to complete your intake information first. " \
                    "Please provide your name, reason for seeking therapy, and insurance details before scheduling.",
        "documents" => "You need to upload and verify your documents (insurance card, ID) " \
                       "before scheduling an appointment. Would you like to upload them now?"
      }

      {
        error: "onboarding_incomplete",
        message: messages[step] || messages["intake"],
        missing_step: step
      }
    end

    def exec_get_current_datetime
      now = Time.now.utc
      mountain_now = now.in_time_zone("America/Denver")

      {
        utc: now.iso8601,
        mountain_time: mountain_now.strftime("%Y-%m-%d %H:%M:%S MDT"),
        date: now.strftime("%A, %B %d, %Y"),
        day_of_week: now.strftime("%A"),
        iso_date: now.strftime("%Y-%m-%d")
      }
    end

    def exec_get_available_slots(input, auth_context)
      therapist_id = input["therapist_id"] || input[:therapist_id]
      therapist_id ||= auth_context.therapist_id if auth_context.role == "client" && auth_context.therapist_id.present?
      return { error: "therapist_id is required. For clients with an assigned therapist, use your assigned therapist's ID." } if therapist_id.blank?

      slots = SchedulingService.get_availability(therapist_id: therapist_id)
      zone = ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE]

      formatted = slots.map do |slot|
        start_utc = Time.parse(slot[:start_time])
        start_local = start_utc.in_time_zone(zone)
        {
          slot_id: slot[:id],
          date: start_local.strftime("%A, %B %d"),
          time: start_local.strftime("%I:%M %p"),
          duration_minutes: slot[:duration_minutes]
        }
      end

      { therapist_id: therapist_id, slots: formatted, total: formatted.length }
    end

    def exec_book_appointment(input, auth_context)
      therapist_id = input["therapist_id"] || input[:therapist_id]
      therapist_id ||= auth_context.therapist_id if auth_context.role == "client" && auth_context.therapist_id.present?
      slot_id = input["slot_id"] || input[:slot_id]

      return { error: "therapist_id is required. For clients with an assigned therapist, use your assigned therapist's ID." } if therapist_id.blank?

      if auth_context.role == "client"
        return { error: "No client profile found for this user" } if auth_context.client_id.nil?
      elsif auth_context.role == "therapist"
        client_id = input["client_id"] || input[:client_id]
        return { error: "Therapist must specify client_id when booking on behalf of a client" } if client_id.nil?
      else
        return { error: "Only clients and therapists can book appointments" }
      end

      # Resolve slot_id to session_date so the booked time matches the selected slot.
      # Slot IDs are therapist_id:ISO8601 (e.g. 5:2026-03-24T19:00:00Z). Also accept ISO8601 datetime for matching.
      slots = SchedulingService.get_availability(therapist_id: therapist_id)
      selected_slot = resolve_slot(slots, slot_id, therapist_id)
      session_date = selected_slot ? Time.parse(selected_slot[:start_time]) : nil
      canonical_slot_id = selected_slot ? selected_slot[:id].to_s : slot_id.to_s

      if auth_context.role == "client"
        SchedulingService.book_appointment(
          client_id: auth_context.client_id,
          therapist_id: therapist_id,
          slot_id: canonical_slot_id,
          session_date: session_date
        )
      else
        client_id = input["client_id"] || input[:client_id]
        SchedulingService.book_appointment(
          client_id: client_id,
          therapist_id: therapist_id,
          slot_id: canonical_slot_id,
          session_date: session_date,
          acting_therapist_id: auth_context.therapist_id
        )
      end
    rescue SchedulingService::ConflictError
      fresh_slots = SchedulingService.get_availability(therapist_id: therapist_id)
      {
        error: "slot_conflict",
        message: "I'm sorry, that time slot was just booked by someone else. Here are the updated available times:",
        available_slots: fresh_slots
      }
    end

    # Resolve slot_id to actual slot. Accepts:
    # - Exact ID from get_available_slots (e.g. "slot-1-14")
    # - X:ISO8601 (LLM-invented, e.g. "5:2026-03-27T13:00:00Z" — match by date + hour)
    # - Raw ISO8601 datetime
    # - "1pm_3_27", "monday_1pm" (dayname_time or time_month_day)
    def resolve_slot(slots, slot_id, therapist_id)
      return nil unless slot_id.is_a?(String)

      zone = ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE]

      # 1. Exact match
      found = slots.find { |s| s[:id].to_s == slot_id.to_s }
      return found if found

      # 2. Parse as X:ISO8601 — match by datetime (prefix ignored; LLM may use index vs therapist_id)
      if slot_id.include?(":")
        _prefix, datetime_str = slot_id.split(":", 2)
        parsed = Time.parse(datetime_str) rescue nil
        if parsed
          found = slots.find { |s| Time.parse(s[:start_time]).utc.to_i == parsed.utc.to_i }
          return found if found
          # No exact UTC match: find slot on same date, same local hour (LLM may confuse UTC vs local)
          target_date = parsed.in_time_zone(zone).to_date
          target_hour = parsed.hour # 13 often means 1pm
          found = slots.find do |s|
            start_local = Time.parse(s[:start_time]).in_time_zone(zone)
            start_local.to_date == target_date && start_local.hour == target_hour
          end
          return found if found
          # Last resort: same date, any slot (pick first)
          found = slots.find do |s|
            Time.parse(s[:start_time]).in_time_zone(zone).to_date == target_date
          end
          return found if found
        end
      end

      # 3. Raw ISO8601 datetime
      if slot_id.match?(/^\d{4}-\d{2}-\d{2}/)
        parsed = Time.parse(slot_id) rescue nil
        if parsed
          found = slots.find { |s| Time.parse(s[:start_time]).utc.to_i == parsed.utc.to_i }
          return found if found
          target_date = parsed.in_time_zone(zone).to_date
          target_hour = parsed.hour
          found = slots.find do |s|
            start_local = Time.parse(s[:start_time]).in_time_zone(zone)
            start_local.to_date == target_date && start_local.hour == target_hour
          end
          return found if found
          found = slots.find { |s| Time.parse(s[:start_time]).in_time_zone(zone).to_date == target_date }
          return found if found
        end
      end

      # 4. LLM-invented formats: "1pm_3_27", "monday_1pm"
      resolve_slot_by_day_time(slots, slot_id)
    end

    # Fallback: match "monday_1pm", "1pm_3_27", "3_27_1pm"
    def resolve_slot_by_day_time(slots, slot_id)
      return nil unless slot_id.is_a?(String) && slot_id.include?("_")

      zone = ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE]
      parts = slot_id.downcase.split("_")

      # dayname_time: "monday_1pm"
      if parts.size == 2
        day_part = parts[0]
        time_part = parts[1]
        target_hour = parse_hour(time_part)
        day_map = %w[sunday monday tuesday wednesday thursday friday saturday].index(day_part)
        if target_hour && day_map
          return slots.find do |slot|
            start_local = Time.parse(slot[:start_time]).in_time_zone(zone)
            start_local.wday == day_map && start_local.hour == target_hour
          end
        end
      end

      # time_month_day: "1pm_3_27" (parts: [1pm, 3, 27])
      if parts.size >= 2
        time_part = parts[0]
        target_hour = parse_hour(time_part)
        month, day = parts.size >= 3 ? parse_month_day(parts[1], parts[2]) : parse_month_day(parts[1], nil)
        if target_hour && month && day
          return slots.find do |slot|
            start_local = Time.parse(slot[:start_time]).in_time_zone(zone)
            start_local.month == month && start_local.day == day && start_local.hour == target_hour
          end
        end
      end

      # month_day_time: "3_27_1pm"
      if parts.size >= 3
        month, day = parse_month_day(parts[0], parts[1])
        target_hour = parse_hour(parts[2])
        if month && day && target_hour
          return slots.find do |slot|
            start_local = Time.parse(slot[:start_time]).in_time_zone(zone)
            start_local.month == month && start_local.day == day && start_local.hour == target_hour
          end
        end
      end

      nil
    end

    def parse_hour(time_str)
      case time_str.to_s.downcase
      when /^12am$/i then 0
      when /^(\d{1,2})am$/i then Regexp.last_match(1).to_i
      when /^12pm$/i then 12
      when /^(\d{1,2})pm$/i then Regexp.last_match(1).to_i + 12
      when /^(\d{1,2})$/ then time_str.to_i
      else nil
      end
    end

    def parse_month_day(part1, part2 = nil)
      m = part1.to_i
      d = part2 ? part2.to_i : nil
      if m >= 1 && m <= 12 && d && d >= 1 && d <= 31
        [m, d]
      elsif part2.nil? && part1.to_s.include?("/")
        month, day = part1.split("/").map(&:to_i)
        (month >= 1 && month <= 12 && day >= 1 && day <= 31) ? [month, day] : nil
      else
        nil
      end
    end

    def exec_search_therapists(input, _auth_context)
      service = therapist_search_service
      results = service.search(
        query: input["query"] || input[:query],
        specialty: input["specialty"] || input[:specialty]
      )

      {
        therapists: results.map { |r| r.to_h },
        total: results.length
      }
    end

    def exec_confirm_therapist(input, auth_context)
      display_label = input["display_label"] || input[:display_label]
      user = User.find(auth_context.user_id)
      conversation = user.conversations.find_by(context_type: "onboarding", status: "active")

      return { error: "No active onboarding conversation found" } unless conversation

      service = therapist_search_service
      therapist_id = service.confirm_selection(conversation: conversation, display_label: display_label)

      if therapist_id
        { confirmed: true, therapist_id: therapist_id }
      else
        { error: "Unknown display label: #{display_label}. Please search again." }
      end
    end

    def therapist_search_service
      @therapist_search_service ||= TherapistSearchService.new
    end

    def exec_check_document_status(auth_context)
      user = User.find(auth_context.user_id)
      conversation = user.conversations.find_by(context_type: "onboarding", status: "active")

      return { docs_verified: false, message: "No active onboarding conversation found" } unless conversation

      progress = conversation.onboarding
      { docs_verified: progress.docs_verified == true }
    end

    def exec_upload_document(input, auth_context)
      document_ref = input["document_ref"] || input[:document_ref]
      return { error: "document_ref is required" } if document_ref.blank?

      user = User.find(auth_context.user_id)
      conversation = user.conversations.find_by(context_type: "onboarding", status: "active")
      return { error: "No active onboarding conversation found" } unless conversation

      doc = conversation.onboarding.find_document(document_ref)
      return { error: "Document not found for reference: #{document_ref}" } unless doc

      {
        found: true,
        redacted_preview: doc[:redacted_preview],
        status: doc[:status]
      }
    end

    def exec_list_appointments(input, auth_context)
      if auth_context.role == "client"
        return { error: "No client profile found for this user" } if auth_context.client_id.nil?

        client_id = auth_context.client_id
      elsif auth_context.role == "therapist"
        client_id = input["client_id"] || input[:client_id]
        return { error: "Therapist must specify client_id when listing on behalf of a client" } if client_id.nil?

        client = Client.find_by(id: client_id)
        return { error: "Client not found" } unless client
        unless client.therapist_id == auth_context.therapist_id
          return { error: "Client is not assigned to this therapist" }
        end
      else
        return { error: "Only clients and therapists can list appointments" }
      end

      sessions = Session
        .where(client_id: client_id, status: "scheduled")
        .where("session_date >= ?", Time.current)
        .includes(therapist: :user)
        .order(:session_date)

      zone = ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE]
      appointments = sessions.map do |s|
        therapist_name = s.therapist&.user&.name || "Your therapist"
        start_local = s.session_date.in_time_zone(zone)
        {
          session_id: s.id,
          date: start_local.strftime("%A, %B %d"),
          time: start_local.strftime("%I:%M %p"),
          duration_minutes: s.duration_minutes,
          therapist_name: therapist_name,
          cancel_payload: "Cancel session #{s.id}"
        }
      end

      { appointments: appointments, total: appointments.length }
    end

    def exec_cancel_appointment(input, auth_context)
      session_id = input["session_id"] || input[:session_id]

      if auth_context.role == "client"
        return { error: "No client profile found for this user" } if auth_context.client_id.nil?

        SchedulingService.cancel_appointment(
          session_id: session_id,
          client_id: auth_context.client_id
        )
      elsif auth_context.role == "therapist"
        client_id = input["client_id"] || input[:client_id]
        return { error: "Therapist must specify client_id when cancelling on behalf of a client" } if client_id.nil?

        SchedulingService.cancel_appointment(
          session_id: session_id,
          client_id: client_id,
          acting_therapist_id: auth_context.therapist_id
        )
      else
        { error: "Only clients and therapists can cancel appointments" }
      end
    end
  end
end
