require "rails_helper"

RSpec.describe "Phantom Booking (slot conflict handling)" do
  let(:therapist) { create(:therapist) }
  let(:client) { create(:client, therapist: therapist) }
  let(:client2) { create(:client, therapist: therapist) }
  let(:slot_id) { "slot-#{therapist.id}-1" }

  let(:auth_context) do
    AgentTools::ToolAuthContext.new(
      user_id: client.user_id || client.id,
      role: "client",
      client_id: client.id,
      therapist_id: nil
    )
  end

  before(:each) { SchedulingService.clear_booked_slots! }

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

      different_slot = "slot-#{therapist.id}-2"
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
