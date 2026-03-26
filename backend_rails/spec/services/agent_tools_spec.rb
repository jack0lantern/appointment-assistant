require "rails_helper"

RSpec.describe AgentTools do
  describe "TOOL_DEFINITIONS" do
    it "has 16 tool definitions" do
      expect(AgentTools::TOOL_DEFINITIONS.length).to eq(16)
    end

    it "each tool has name, description, and input_schema" do
      AgentTools::TOOL_DEFINITIONS.each do |tool|
        expect(tool).to have_key(:name), "Tool missing :name"
        expect(tool).to have_key(:description), "Tool #{tool[:name]} missing :description"
        expect(tool).to have_key(:input_schema), "Tool #{tool[:name]} missing :input_schema"
        expect(tool[:input_schema]).to have_key(:type)
        expect(tool[:input_schema][:type]).to eq("object")
      end
    end

    it "includes all expected tool names" do
      names = AgentTools::TOOL_DEFINITIONS.map { |t| t[:name] }
      %w[
        get_current_datetime get_available_slots book_appointment list_appointments cancel_appointment
        get_grounding_exercise get_psychoeducation get_what_to_expect get_validation_message
        search_therapists confirm_therapist check_document_status upload_document search_clients set_suggested_actions
      ].each do |expected|
        expect(names).to include(expected)
      end
    end
  end

  describe "ToolAuthContext" do
    it "stores user_id, role, client_id, and therapist_id" do
      ctx = AgentTools::ToolAuthContext.new(
        user_id: 1, role: "client", client_id: 10, therapist_id: 5
      )
      expect(ctx.user_id).to eq(1)
      expect(ctx.role).to eq("client")
      expect(ctx.client_id).to eq(10)
      expect(ctx.therapist_id).to eq(5)
    end

    it "defaults client_id and therapist_id to nil" do
      ctx = AgentTools::ToolAuthContext.new(user_id: 1, role: "client")
      expect(ctx.client_id).to be_nil
      expect(ctx.therapist_id).to be_nil
    end
  end

  describe ".execute_tool" do
    let(:client_auth) do
      AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: 10, therapist_id: 5)
    end

    let(:therapist_auth) do
      AgentTools::ToolAuthContext.new(user_id: 2, role: "therapist", client_id: nil, therapist_id: 5)
    end

    describe "get_current_datetime" do
      it "returns datetime info" do
        result = described_class.execute_tool(
          name: "get_current_datetime",
          auth_context: client_auth
        )
        expect(result).to have_key(:utc)
        expect(result).to have_key(:mountain_time)
        expect(result).to have_key(:date)
        expect(result).to have_key(:day_of_week)
        expect(result).to have_key(:iso_date)
      end
    end

    describe "get_grounding_exercise" do
      it "returns an exercise and citation for the user-facing reply" do
        result = described_class.execute_tool(
          name: "get_grounding_exercise",
          auth_context: client_auth
        )
        expect(result).to have_key(:exercise)
        expect(result[:exercise]).to be_a(String)
        expect(result[:exercise]).not_to be_empty
        expect(result).to have_key(:citation)
        expect(result[:citation]).to include("http")
      end
    end

    describe "get_psychoeducation" do
      it "returns content and citation for a valid topic" do
        result = described_class.execute_tool(
          name: "get_psychoeducation",
          input: { "topic" => "anxiety" },
          auth_context: client_auth
        )
        expect(result).to have_key(:content)
        expect(result).to have_key(:citation)
        expect(result[:citation]).to include("http")
      end

      it "returns error for an invalid topic" do
        result = described_class.execute_tool(
          name: "get_psychoeducation",
          input: { "topic" => "nonexistent" },
          auth_context: client_auth
        )
        expect(result).to have_key(:error)
        expect(result[:error]).to include("Unknown topic")
      end
    end

    describe "get_what_to_expect" do
      it "returns content and citation for a valid context" do
        result = described_class.execute_tool(
          name: "get_what_to_expect",
          input: { "context" => "onboarding" },
          auth_context: client_auth
        )
        expect(result).to have_key(:content)
        expect(result).to have_key(:citation)
        expect(result[:citation]).to include("http")
      end

      it "returns error for an invalid context" do
        result = described_class.execute_tool(
          name: "get_what_to_expect",
          input: { "context" => "nonexistent" },
          auth_context: client_auth
        )
        expect(result).to have_key(:error)
        expect(result[:error]).to include("Unknown context")
      end
    end

    describe "get_validation_message" do
      it "returns a message" do
        result = described_class.execute_tool(
          name: "get_validation_message",
          auth_context: client_auth
        )
        expect(result).to have_key(:message)
        expect(result[:message]).to be_a(String)
      end
    end

    describe "upload_document" do
      it "returns document info when document_ref exists in onboarding" do
        user = create(:user, :client)
        doc_ref = SecureRandom.uuid
        conversation = create(:conversation, :onboarding, user: user, onboarding_progress: {
          uploaded_documents: [
            { document_ref: doc_ref, redacted_preview: "Insurance card: [NAME_1], policy [POLICY_1]", status: "verified" }
          ]
        })
        auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)

        result = described_class.execute_tool(
          name: "upload_document",
          input: { "document_ref" => doc_ref },
          auth_context: auth
        )

        expect(result).to have_key(:found)
        expect(result[:found]).to eq(true)
        expect(result[:redacted_preview]).to eq("Insurance card: [NAME_1], policy [POLICY_1]")
        expect(result[:status]).to eq("verified")
      end

      it "returns error when document_ref not found" do
        user = create(:user, :client)
        create(:conversation, :onboarding, user: user, onboarding_progress: { uploaded_documents: [] })
        auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)

        result = described_class.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "nonexistent-ref" },
          auth_context: auth
        )

        expect(result).to have_key(:error)
        expect(result[:error]).to include("Document not found")
      end

      it "returns error when no active onboarding conversation" do
        user = create(:user, :client)
        auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)

        result = described_class.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "any-ref" },
          auth_context: auth
        )

        expect(result).to have_key(:error)
        expect(result[:error]).to include("No active onboarding conversation")
      end
    end

    describe "set_suggested_actions" do
      it "returns success (AgentService captures input for buttons)" do
        result = described_class.execute_tool(
          name: "set_suggested_actions",
          input: {
            "actions" => [
              { "label" => "Anxiety", "payload" => "I'm dealing with anxiety" },
              { "label" => "Depression", "payload" => "I'm dealing with depression" }
            ]
          },
          auth_context: client_auth
        )
        expect(result).to eq({ success: true })
      end
    end

    describe "unknown tool" do
      it "returns an error" do
        result = described_class.execute_tool(
          name: "nonexistent_tool",
          auth_context: client_auth
        )
        expect(result).to have_key(:error)
        expect(result[:error]).to include("Unknown tool")
      end
    end

    describe "search_clients" do
      it "returns matching clients for a therapist" do
        therapist = create(:therapist)
        client1 = create(:client, therapist: therapist, name: "Alice Johnson")
        client2 = create(:client, therapist: therapist, name: "Bob Smith")
        _other_client = create(:client, name: "Alice Other") # different therapist

        auth = AgentTools::ToolAuthContext.new(user_id: therapist.user_id, role: "therapist", therapist_id: therapist.id)
        result = described_class.execute_tool(
          name: "search_clients",
          input: { "query" => "Alice" },
          auth_context: auth
        )

        expect(result[:clients]).to be_a(Array)
        expect(result[:clients].length).to eq(1)
        expect(result[:clients].first[:name]).to eq("Alice Johnson")
        expect(result[:clients].first[:client_id]).to eq(client1.id)
      end

      it "returns all clients when query is blank" do
        therapist = create(:therapist)
        create(:client, therapist: therapist, name: "Alice Johnson")
        create(:client, therapist: therapist, name: "Bob Smith")

        auth = AgentTools::ToolAuthContext.new(user_id: therapist.user_id, role: "therapist", therapist_id: therapist.id)
        result = described_class.execute_tool(
          name: "search_clients",
          input: {},
          auth_context: auth
        )

        expect(result[:clients].length).to eq(2)
      end

      it "returns error when called by a client" do
        auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: 10)
        result = described_class.execute_tool(
          name: "search_clients",
          input: { "query" => "Alice" },
          auth_context: auth
        )

        expect(result[:error]).to include("Only therapists")
      end

      it "returns empty array when no clients match" do
        therapist = create(:therapist)
        create(:client, therapist: therapist, name: "Bob Smith")

        auth = AgentTools::ToolAuthContext.new(user_id: therapist.user_id, role: "therapist", therapist_id: therapist.id)
        result = described_class.execute_tool(
          name: "search_clients",
          input: { "query" => "Nonexistent" },
          auth_context: auth
        )

        expect(result[:clients]).to eq([])
        expect(result[:total]).to eq(0)
      end
    end

    describe "auth validation for scheduling tools" do
      describe "book_appointment" do
        it "returns error when client has no client_id" do
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: nil)
          result = described_class.execute_tool(
            name: "book_appointment",
            input: { "therapist_id" => 5, "slot_id" => "5:2026-03-24T19:00:00Z" },
            auth_context: auth
          )
          # Onboarding guard catches missing client_id before exec_book_appointment
          expect(result[:error]).to eq("onboarding_incomplete")
        end

        it "returns error when therapist omits client_id" do
          result = described_class.execute_tool(
            name: "book_appointment",
            input: { "therapist_id" => 5, "slot_id" => "5:2026-03-24T19:00:00Z" },
            auth_context: therapist_auth
          )
          expect(result[:error]).to include("must specify client_id")
        end

        it "returns error for unauthorized role" do
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "admin")
          result = described_class.execute_tool(
            name: "book_appointment",
            input: { "therapist_id" => 5, "slot_id" => "5:2026-03-24T19:00:00Z" },
            auth_context: auth
          )
          expect(result[:error]).to include("Only clients and therapists")
        end
      end

      describe "list_appointments" do
        it "returns error when client has no client_id" do
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: nil)
          result = described_class.execute_tool(
            name: "list_appointments",
            input: {},
            auth_context: auth
          )
          expect(result[:error]).to include("No client profile")
        end

        it "returns error when therapist omits client_id" do
          result = described_class.execute_tool(
            name: "list_appointments",
            input: {},
            auth_context: therapist_auth
          )
          expect(result[:error]).to include("must specify client_id")
        end

        it "returns error when therapist lists appointments for client not assigned to them" do
          other_therapist = create(:therapist)
          other_client = create(:client, therapist: other_therapist)
          create(:session, therapist: other_therapist, client: other_client, status: "scheduled", session_date: 2.days.from_now)

          auth = AgentTools::ToolAuthContext.new(user_id: therapist_auth.user_id, role: "therapist", therapist_id: therapist_auth.therapist_id)
          result = described_class.execute_tool(
            name: "list_appointments",
            input: { "client_id" => other_client.id },
            auth_context: auth
          )

          expect(result[:error]).to be_present
          expect(result[:error]).to include("not assigned")
        end

        it "returns appointments when therapist lists for their assigned client" do
          therapist = create(:therapist)
          client = create(:client, therapist: therapist)
          create(:session, therapist: therapist, client: client, status: "scheduled", session_date: 2.days.from_now)

          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "therapist", therapist_id: therapist.id)
          result = described_class.execute_tool(
            name: "list_appointments",
            input: { "client_id" => client.id },
            auth_context: auth
          )

          expect(result[:error]).to be_nil
          expect(result[:appointments].length).to eq(1)
        end

        it "returns appointments for client with scheduled sessions" do
          therapist = create(:therapist)
          client = create(:client, therapist: therapist)
          create(:session, therapist: therapist, client: client, status: "scheduled", session_date: 2.days.from_now)
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: client.id, therapist_id: therapist.id)
          result = described_class.execute_tool(
            name: "list_appointments",
            input: {},
            auth_context: auth
          )
          expect(result[:appointments]).to be_a(Array)
          expect(result[:appointments].length).to eq(1)
          expect(result[:appointments].first).to include(:session_id, :date, :time, :therapist_name, :cancel_payload)
        end

        it "returns empty list when no scheduled sessions" do
          client = create(:client)
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: client.id)
          result = described_class.execute_tool(
            name: "list_appointments",
            input: {},
            auth_context: auth
          )
          expect(result[:appointments]).to eq([])
          expect(result[:total]).to eq(0)
        end

        it "returns error for unauthorized role" do
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "admin")
          result = described_class.execute_tool(
            name: "list_appointments",
            input: {},
            auth_context: auth
          )
          expect(result[:error]).to include("Only clients and therapists")
        end
      end

      describe "cancel_appointment" do
        it "returns error when client has no client_id" do
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "client", client_id: nil)
          result = described_class.execute_tool(
            name: "cancel_appointment",
            input: { "session_id" => 1 },
            auth_context: auth
          )
          expect(result[:error]).to include("No client profile")
        end

        it "returns error when therapist omits client_id" do
          result = described_class.execute_tool(
            name: "cancel_appointment",
            input: { "session_id" => 1 },
            auth_context: therapist_auth
          )
          expect(result[:error]).to include("must specify client_id")
        end

        it "returns error for unauthorized role" do
          auth = AgentTools::ToolAuthContext.new(user_id: 1, role: "admin")
          result = described_class.execute_tool(
            name: "cancel_appointment",
            input: { "session_id" => 1 },
            auth_context: auth
          )
          expect(result[:error]).to include("Only clients and therapists")
        end
      end
    end
  end
end
