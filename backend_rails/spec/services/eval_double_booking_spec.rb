# frozen_string_literal: true

require "rails_helper"

# Evaluation: A booked slot must not be bookable again for the same therapist.
# Tests double-booking prevention at the SchedulingService, AgentTools, and
# full agent pipeline levels, including across different slot_id formats and
# multiple clients.
RSpec.describe "Double-booking prevention evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  let!(:therapist) { create(:therapist) }
  let(:user1) { create(:user, :client) }
  let(:user2) { create(:user, :client) }
  let!(:client1) { create(:client, user: user1, therapist: therapist) }
  let!(:client2) { create(:client, user: user2, therapist: therapist) }

  let(:slots) { SchedulingService.get_availability(therapist_id: therapist.id) }
  let(:target_slot) { slots.first }
  let(:slot_id) { target_slot[:id] }

  def auth_for(user, client)
    AgentTools::ToolAuthContext.new(
      user_id: user.id,
      role: "client",
      client_id: client.id,
      therapist_id: therapist.id
    )
  end

  before do
    user1.reload
    user2.reload
    SchedulingService.clear_booked_slots!
  end

  # ---------------------------------------------------------------------------
  # Same slot, two different clients
  # ---------------------------------------------------------------------------
  describe "two clients booking the same slot" do
    it "first client succeeds, second client gets slot_conflict error" do
      result1 = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user1, client1)
      )

      expect(result1[:status]).to eq("confirmed")

      result2 = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user2, client2)
      )

      expect(result2[:error]).to eq("slot_conflict")
      expect(result2[:message]).to match(/sorry/i)
      expect(result2[:available_slots]).to be_an(Array)
    end

    it "only one Session record exists for the booked slot" do
      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user1, client1)
      )

      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user2, client2)
      )

      expected_time = Time.parse(target_slot[:start_time])
      sessions = Session.where(therapist_id: therapist.id, status: "scheduled")
        .where("session_date BETWEEN ? AND ?", expected_time - 1.minute, expected_time + 1.minute)

      expect(sessions.count).to eq(1)
      expect(sessions.first.client_id).to eq(client1.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Same client trying to double-book the same slot
  # ---------------------------------------------------------------------------
  describe "same client booking the same slot twice" do
    it "rejects the second booking attempt" do
      auth = auth_for(user1, client1)

      result1 = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth
      )
      expect(result1[:status]).to eq("confirmed")

      result2 = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth
      )
      expect(result2[:error]).to eq("slot_conflict")
    end
  end

  # ---------------------------------------------------------------------------
  # Different slot_id formats that resolve to the same slot are still blocked
  # ---------------------------------------------------------------------------
  describe "equivalent slot_id formats are blocked after booking" do
    it "blocks raw ISO8601 after exact slot_id was booked" do
      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user1, client1)
      )

      # Second client tries with the raw start_time string
      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: target_slot[:start_time] },
        auth_context: auth_for(user2, client2)
      )

      expect(result[:error]).to eq("slot_conflict")
    end

    it "blocks exact slot_id after raw ISO8601 was booked" do
      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: target_slot[:start_time] },
        auth_context: auth_for(user1, client1)
      )

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user2, client2)
      )

      expect(result[:error]).to eq("slot_conflict")
    end

    it "blocks LLM-fabricated local-as-UTC slot_id after exact slot_id was booked" do
      zone = ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE]
      slot_local = Time.parse(target_slot[:start_time]).in_time_zone(zone)
      fabricated = "#{therapist.id}:#{slot_local.strftime('%Y-%m-%dT%H:%M:%S')}Z"

      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user1, client1)
      )

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: fabricated },
        auth_context: auth_for(user2, client2)
      )

      expect(result[:error]).to eq("slot_conflict")
    end
  end

  # ---------------------------------------------------------------------------
  # Different slots for the same therapist remain bookable
  # ---------------------------------------------------------------------------
  describe "different slots remain available after a booking" do
    it "second client can book a different time slot" do
      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slots.first[:id] },
        auth_context: auth_for(user1, client1)
      )

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slots.second[:id] },
        auth_context: auth_for(user2, client2)
      )

      expect(result[:status]).to eq("confirmed")
      expect(Session.where(therapist_id: therapist.id, status: "scheduled").count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end: agent pipeline handles double-booking with conflict response
  # ---------------------------------------------------------------------------
  describe "agent pipeline double-booking" do
    it "second client agent gets conflict error and is offered fresh slots" do
      # Client 1 books directly
      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_for(user1, client1)
      )

      # Client 2 goes through the agent flow and attempts the same slot
      alternative_slot = slots.second
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 2
          # LLM picks the already-booked slot
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => slot_id } }] }
        when 3
          # After conflict, LLM retries with a different slot
          { "content" => [{ "type" => "tool_use", "id" => "t3", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => alternative_slot[:id] } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Your appointment has been booked!" }] }
        end
      end

      result = service.process_message(
        message: "I'd like to book an appointment",
        user: user2,
        context_type: "scheduling"
      )

      expect(call_count).to eq(4)
      expect(result[:message]).to include("booked")

      # Verify two distinct sessions exist for different clients
      all_scheduled = Session.where(therapist_id: therapist.id, status: "scheduled").order(:client_id)
      expect(all_scheduled.count).to eq(2)
      expect(all_scheduled.map(&:client_id)).to contain_exactly(client1.id, client2.id)

      # Verify sessions are at different times
      expect(all_scheduled.first.session_date).not_to eq(all_scheduled.second.session_date)
    end
  end
end
