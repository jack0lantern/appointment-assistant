require "rails_helper"

RSpec.describe "Phantom Booking (slot conflict handling)" do
  let(:therapist) { create(:therapist) }
  let(:client) { create(:client, therapist: therapist) }
  let(:client2) { create(:client, therapist: therapist) }
  let(:slot_id) { SchedulingService.get_availability(therapist_id: therapist.id).first[:id] }

  let(:auth_context) do
    AgentTools::ToolAuthContext.new(
      user_id: client.user_id || client.id,
      role: "client",
      client_id: client.id,
      therapist_id: nil
    )
  end


  describe "SchedulingService conflict detection" do
    it "raises ConflictError when booking an already-booked slot" do
      SchedulingService.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id
      )

      expect {
        SchedulingService.book_appointment(
          client_id: client2.id,
          therapist_id: therapist.id,
          slot_id: slot_id
        )
      }.to raise_error(SchedulingService::ConflictError, /already booked/i)
    end

    it "succeeds on retry with a different slot" do
      SchedulingService.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id
      )

      different_slot = SchedulingService.get_availability(therapist_id: therapist.id).second[:id]
      result = SchedulingService.book_appointment(
        client_id: client2.id,
        therapist_id: therapist.id,
        slot_id: different_slot
      )

      expect(result[:status]).to eq("confirmed")
      expect(result[:slot_id]).to eq(different_slot)
    end

    it "handles concurrent booking race condition (same slot, two clients)" do
      # First booking succeeds
      result1 = SchedulingService.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id
      )
      expect(result1[:status]).to eq("confirmed")

      # Second booking for same slot fails
      expect {
        SchedulingService.book_appointment(
          client_id: client2.id,
          therapist_id: therapist.id,
          slot_id: slot_id
        )
      }.to raise_error(SchedulingService::ConflictError)
    end
  end

  describe "AgentTools therapist fallback for assigned clients" do
    it "uses client's assigned therapist when therapist_id omitted in get_available_slots" do
      auth = AgentTools::ToolAuthContext.new(
        user_id: client.user_id || client.id,
        role: "client",
        client_id: client.id,
        therapist_id: therapist.id
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: {},
        auth_context: auth
      )

      expect(result[:error]).to be_nil
      expect(result[:therapist_id]).to eq(therapist.id)
      expect(result[:days]).to be_an(Array)
      expect(result[:days]).not_to be_empty
    end

    it "uses client's assigned therapist when therapist_id omitted in book_appointment" do
      auth = AgentTools::ToolAuthContext.new(
        user_id: client.user_id || client.id,
        role: "client",
        client_id: client.id,
        therapist_id: therapist.id
      )

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { slot_id: slot_id },
        auth_context: auth
      )

      expect(result[:error]).to be_nil
      expect(result[:status]).to eq("confirmed")
      expect(Session.find(result[:session_id]).therapist_id).to eq(therapist.id)
    end
  end

  describe "AgentTools session_date from slot" do
    it "books with session_date matching the selected slot's start time" do
      slots = SchedulingService.get_availability(therapist_id: therapist.id)
      first_slot = slots.first
      expected_start = Time.parse(first_slot[:start_time])

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: first_slot[:id] },
        auth_context: auth_context
      )

      expect(result[:error]).to be_nil
      expect(result[:status]).to eq("confirmed")
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.minute).of(expected_start)
    end

    it "resolves ISO8601 datetime slot_id to correct session_date" do
      slots = SchedulingService.get_availability(therapist_id: therapist.id)
      first_slot = slots.first
      start_iso = first_slot[:start_time]

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: start_iso },
        auth_context: auth_context
      )

      expect(result[:error]).to be_nil
      expect(result[:status]).to eq("confirmed")
      expected_start = Time.parse(start_iso)
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.minute).of(expected_start)
    end
  end

  describe "AgentTools conflict response" do
    it "returns fresh slots on booking conflict" do
      # Book the slot first
      SchedulingService.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id
      )

      # Try to book same slot via AgentTools
      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_context
      )

      expect(result[:error]).to eq("slot_conflict")
      expect(result[:available_slots]).to be_an(Array)
      expect(result[:available_slots]).not_to be_empty
    end

    it "includes apology in conflict response" do
      SchedulingService.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id
      )

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot_id },
        auth_context: auth_context
      )

      expect(result[:message]).to match(/sorry/i)
      expect(result[:message]).to match(/booked/i)
    end
  end
end
