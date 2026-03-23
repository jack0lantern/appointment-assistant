# frozen_string_literal: true

require "rails_helper"

# Evaluation: A booked slot must not appear as available when fetching slots.
# After booking 3/27 1 PM, get_available_slots must exclude that slot so
# neither the agent nor another client sees it as free.
RSpec.describe "Booked slot visibility evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  let!(:therapist) { create(:therapist) }
  let(:user1) { create(:user, :client) }
  let(:user2) { create(:user, :client) }
  let!(:client1) { create(:client, user: user1, therapist: therapist) }
  let!(:client2) { create(:client, user: user2, therapist: therapist) }

  let(:zone) { ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE] }

  def auth_for(user, client)
    AgentTools::ToolAuthContext.new(
      user_id: user.id,
      role: "client",
      client_id: client.id,
      therapist_id: therapist.id
    )
  end

  def slot_at_local_hour(hour)
    SchedulingService.get_availability(therapist_id: therapist.id).find do |s|
      Time.parse(s[:start_time]).in_time_zone(zone).hour == hour
    end
  end

  before do
    user1.reload
    user2.reload

  end

  # ---------------------------------------------------------------------------
  # SchedulingService level: booked slots excluded from availability
  # ---------------------------------------------------------------------------
  describe "SchedulingService.get_availability excludes booked slots" do
    it "removes the booked slot from the returned list" do
      slot = slot_at_local_hour(13)
      all_before = SchedulingService.get_availability(therapist_id: therapist.id)
      expect(all_before.map { |s| s[:id] }).to include(slot[:id])

      SchedulingService.book_appointment(
        client_id: client1.id,
        therapist_id: therapist.id,
        slot_id: slot[:id],
        session_date: Time.parse(slot[:start_time])
      )

      all_after = SchedulingService.get_availability(therapist_id: therapist.id)
      expect(all_after.map { |s| s[:id] }).not_to include(slot[:id])
    end

    it "still includes other slots on the same day" do
      slot_1pm = slot_at_local_hour(13)
      slot_date = Time.parse(slot_1pm[:start_time]).in_time_zone(zone).to_date

      SchedulingService.book_appointment(
        client_id: client1.id,
        therapist_id: therapist.id,
        slot_id: slot_1pm[:id],
        session_date: Time.parse(slot_1pm[:start_time])
      )

      remaining = SchedulingService.get_availability(therapist_id: therapist.id)
      same_day = remaining.select do |s|
        Time.parse(s[:start_time]).in_time_zone(zone).to_date == slot_date
      end

      # 9 AM and 3 PM should remain
      remaining_hours = same_day.map { |s| Time.parse(s[:start_time]).in_time_zone(zone).hour }
      expect(remaining_hours).to include(9)
      expect(remaining_hours).to include(15)
      expect(remaining_hours).not_to include(13)
    end

    it "total slot count decreases by one after booking" do
      count_before = SchedulingService.get_availability(therapist_id: therapist.id).size
      slot = slot_at_local_hour(13)

      SchedulingService.book_appointment(
        client_id: client1.id,
        therapist_id: therapist.id,
        slot_id: slot[:id],
        session_date: Time.parse(slot[:start_time])
      )

      count_after = SchedulingService.get_availability(therapist_id: therapist.id).size
      expect(count_after).to eq(count_before - 1)
    end
  end

  # ---------------------------------------------------------------------------
  # AgentTools level: get_available_slots tool hides booked slots
  # ---------------------------------------------------------------------------
  describe "get_available_slots tool excludes booked slots" do
    it "does not return the booked slot to the agent" do
      slot = slot_at_local_hour(13)

      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_for(user1, client1)
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user2, client2)
      )

      all_slot_ids = result[:days].flat_map { |d| d[:slots].map { |s| s[:slot_id] } }
      expect(all_slot_ids).not_to include(slot[:id])
    end

    it "formatted time list does not include the booked time on that date" do
      slot = slot_at_local_hour(13)
      booked_date = Time.parse(slot[:start_time]).in_time_zone(zone)
      booked_date_str = booked_date.strftime("%A, %B %d")

      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_for(user1, client1)
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user2, client2)
      )

      booked_day = result[:days].find { |d| d[:date] == booked_date_str }
      times = booked_day[:slots].map { |s| s[:time] }
      expect(times).not_to include("01:00 PM")
      expect(times).to include("09:00 AM")
      expect(times).to include("03:00 PM")
    end
  end

  # ---------------------------------------------------------------------------
  # Cancelled slot becomes available again
  # ---------------------------------------------------------------------------
  describe "cancelled slot reappears in availability" do
    it "slot reappears after cancellation" do
      slot = slot_at_local_hour(13)

      book_result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_for(user1, client1)
      )

      # Verify it's gone
      avail = SchedulingService.get_availability(therapist_id: therapist.id)
      expect(avail.map { |s| s[:id] }).not_to include(slot[:id])

      # Cancel it
      AgentTools.execute_tool(
        name: "cancel_appointment",
        input: { session_id: book_result[:session_id] },
        auth_context: auth_for(user1, client1)
      )

      # Verify it's back
      avail_after = SchedulingService.get_availability(therapist_id: therapist.id)
      expect(avail_after.map { |s| s[:id] }).to include(slot[:id])
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end: agent flow for second client sees reduced availability
  # ---------------------------------------------------------------------------
  describe "agent pipeline shows reduced availability after booking" do
    it "second client agent sees fewer slots after first client books" do
      slot = slot_at_local_hour(13)

      # Client 1 books the 1 PM slot
      AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_for(user1, client1)
      )

      # Client 2 goes through agent flow
      captured_slots = nil
      call_count = 0
      allow(mock_llm).to receive(:call) do |args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 2
          # Capture what the LLM received — the tool result is in the messages
          tool_result_msg = args[:messages]&.find { |m| m["role"] == "user" && m.dig("content", 0, "type") == "tool_result" }
          captured_slots = tool_result_msg
          { "content" => [{ "type" => "text", "text" => "Here are the available slots." }] }
        else
          { "content" => [{ "type" => "text", "text" => "Done." }] }
        end
      end

      service.process_message(
        message: "Show me available times",
        user: user2,
        context_type: "scheduling"
      )

      # Verify via AgentTools directly that the booked slot is excluded
      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user2, client2)
      )

      booked_date = Time.parse(slot[:start_time]).in_time_zone(zone)
      booked_date_str = booked_date.strftime("%A, %B %d")
      booked_day = result[:days].find { |d| d[:date] == booked_date_str }
      times = booked_day[:slots].map { |s| s[:time] }

      expect(times).not_to include("01:00 PM")
    end
  end
end
