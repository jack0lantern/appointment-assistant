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
        "Use this when the user wants to schedule or reschedule an appointment.",
      input_schema: {
        type: "object",
        properties: {
          therapist_id: {
            type: "integer",
            description: "The therapist's ID. Use the user's assigned therapist if known."
          }
        },
        required: ["therapist_id"]
      }
    },
    {
      name: "book_appointment",
      description:
        "Books an appointment for the user (or the therapist's client in delegation mode). " \
        "You MUST call get_available_slots first to get valid slot IDs. " \
        "Pass the slot_id and therapist_id. The backend resolves the real client identity from auth.",
      input_schema: {
        type: "object",
        properties: {
          therapist_id: {
            type: "integer",
            description: "The therapist to book with."
          },
          slot_id: {
            type: "string",
            description: "The slot ID from get_available_slots."
          },
          client_id: {
            type: "integer",
            description:
              "Only required when a therapist is booking on behalf of a client. " \
              "Omit when the user is a client (their identity comes from auth)."
          }
        },
        required: %w[therapist_id slot_id]
      }
    },
    {
      name: "cancel_appointment",
      description:
        "Cancels an existing appointment by session ID. " \
        "The backend validates that the caller owns the session.",
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
        "Returns display labels (e.g. 'Dr. A') instead of raw IDs.",
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
        "Confirm therapist selection by display label after searching. " \
        "Saves the selected therapist to the onboarding conversation.",
      input_schema: {
        type: "object",
        properties: {
          display_label: { type: "string", description: "The display label from search results (e.g. 'Dr. A')." }
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
      exec_get_available_slots(input)

    when "book_appointment"
      exec_book_appointment(input, auth_context)

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

    else
      { error: "Unknown tool: #{name}" }
    end
  rescue StandardError => e
    Rails.logger.error("Tool #{name} error: #{e.message}")
    { error: e.message }
  end

  class << self
    private

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

    def exec_get_available_slots(input)
      therapist_id = input["therapist_id"] || input[:therapist_id]
      slots = SchedulingService.get_availability(therapist_id: therapist_id)

      formatted = slots.map do |slot|
        start = Time.parse(slot[:start_time])
        {
          slot_id: slot[:id],
          date: start.strftime("%A, %B %d"),
          time: start.strftime("%I:%M %p"),
          duration_minutes: slot[:duration_minutes]
        }
      end

      { therapist_id: therapist_id, slots: formatted, total: formatted.length }
    end

    def exec_book_appointment(input, auth_context)
      therapist_id = input["therapist_id"] || input[:therapist_id]
      slot_id = input["slot_id"] || input[:slot_id]

      if auth_context.role == "client"
        return { error: "No client profile found for this user" } if auth_context.client_id.nil?

        SchedulingService.book_appointment(
          client_id: auth_context.client_id,
          therapist_id: therapist_id,
          slot_id: slot_id
        )
      elsif auth_context.role == "therapist"
        client_id = input["client_id"] || input[:client_id]
        return { error: "Therapist must specify client_id when booking on behalf of a client" } if client_id.nil?

        SchedulingService.book_appointment(
          client_id: client_id,
          therapist_id: therapist_id,
          slot_id: slot_id,
          acting_therapist_id: auth_context.therapist_id
        )
      else
        { error: "Only clients and therapists can book appointments" }
      end
    rescue SchedulingService::ConflictError
      fresh_slots = SchedulingService.get_availability(therapist_id: therapist_id)
      {
        error: "slot_conflict",
        message: "I'm sorry, that time slot was just booked by someone else. Here are the updated available times:",
        available_slots: fresh_slots
      }
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
