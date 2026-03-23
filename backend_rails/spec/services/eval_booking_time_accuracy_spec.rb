# frozen_string_literal: true

require "rails_helper"

# Evaluation: Booking an appointment stores the correct time in the database.
# Verifies that the session_date saved to the Session record matches the
# selected slot's start_time, regardless of which slot_id format the LLM uses.
RSpec.describe "Booking time accuracy evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  let(:user) { create(:user, :client) }
  let!(:therapist) { create(:therapist) }
  let!(:client_record) { create(:client, user: user, therapist: therapist) }

  let(:auth_context) do
    AgentTools::ToolAuthContext.new(
      user_id: user.id,
      role: "client",
      client_id: client_record.id,
      therapist_id: therapist.id
    )
  end

  let(:zone) { ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE] }

  before do
    user.reload

  end

  # ---------------------------------------------------------------------------
  # Helper: pick a specific slot (by local hour) from the generated availability
  # ---------------------------------------------------------------------------
  def slot_at_local_hour(hour)
    slots = SchedulingService.get_availability(therapist_id: therapist.id)
    slots.find do |s|
      Time.parse(s[:start_time]).in_time_zone(zone).hour == hour
    end
  end

  # ---------------------------------------------------------------------------
  # Core: exact slot_id → correct session_date in DB
  # ---------------------------------------------------------------------------
  describe "session_date matches selected slot" do
    it "stores the exact UTC start_time of the 1 PM Mountain slot" do
      slot = slot_at_local_hour(13)
      expected_utc = Time.parse(slot[:start_time])

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_context
      )

      expect(result[:status]).to eq("confirmed")
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.second).of(expected_utc)

      # Verify the local hour is 1 PM Mountain, not shifted
      local_hour = session.session_date.in_time_zone(zone).hour
      expect(local_hour).to eq(13)
    end

    it "stores the exact UTC start_time of the 9 AM Mountain slot" do
      slot = slot_at_local_hour(9)
      expected_utc = Time.parse(slot[:start_time])

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_context
      )

      expect(result[:status]).to eq("confirmed")
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.second).of(expected_utc)
      expect(session.session_date.in_time_zone(zone).hour).to eq(9)
    end

    it "stores the exact UTC start_time of the 3 PM Mountain slot" do
      slot = slot_at_local_hour(15)
      expected_utc = Time.parse(slot[:start_time])

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_context
      )

      expect(result[:status]).to eq("confirmed")
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.second).of(expected_utc)
      expect(session.session_date.in_time_zone(zone).hour).to eq(15)
    end
  end

  # ---------------------------------------------------------------------------
  # LLM-constructed slot_id formats → still correct DB time
  # ---------------------------------------------------------------------------
  describe "LLM-constructed slot_id formats resolve to correct DB time" do
    it "handles LLM sending local time as UTC (e.g. '5:2026-03-27T13:00:00Z' for 1 PM Mountain)" do
      slot = slot_at_local_hour(13)
      expected_utc = Time.parse(slot[:start_time])
      slot_date = expected_utc.in_time_zone(zone).to_date

      # LLM mistakenly treats 1 PM local as 13:00 UTC
      fabricated_slot_id = "#{therapist.id}:#{slot_date.strftime('%Y-%m-%d')}T13:00:00Z"

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: fabricated_slot_id },
        auth_context: auth_context
      )

      expect(result[:status]).to eq("confirmed")
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.second).of(expected_utc)
      expect(session.session_date.in_time_zone(zone).hour).to eq(13)
    end

    it "handles raw ISO8601 datetime slot_id" do
      slot = slot_at_local_hour(13)
      expected_utc = Time.parse(slot[:start_time])

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:start_time] },
        auth_context: auth_context
      )

      expect(result[:status]).to eq("confirmed")
      session = Session.find(result[:session_id])
      expect(session.session_date).to be_within(1.second).of(expected_utc)
      expect(session.session_date.in_time_zone(zone).hour).to eq(13)
    end
  end

  # ---------------------------------------------------------------------------
  # display_date / display_time in tool result match the DB time
  # ---------------------------------------------------------------------------
  describe "tool result display fields match DB time" do
    it "returns display_date and display_time in Mountain time" do
      slot = slot_at_local_hour(13)
      expected_utc = Time.parse(slot[:start_time])
      expected_local = expected_utc.in_time_zone(zone)

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_context
      )

      expect(result[:display_time]).to eq(expected_local.strftime("%I:%M %p"))
      expect(result[:display_date]).to eq(expected_local.strftime("%A, %B %d"))
    end

    it "display_time matches the session_date converted to Mountain" do
      slot = slot_at_local_hour(15)

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { therapist_id: therapist.id, slot_id: slot[:id] },
        auth_context: auth_context
      )

      session = Session.find(result[:session_id])
      session_local = session.session_date.in_time_zone(zone)

      expect(result[:display_time]).to eq(session_local.strftime("%I:%M %p"))
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end: agent flow books correct time and display matches
  # ---------------------------------------------------------------------------
  describe "end-to-end agent booking with time validation" do
    it "agent books 1 PM slot and DB session_date is 1 PM Mountain" do
      target_slot = slot_at_local_hour(13)
      expected_utc = Time.parse(target_slot[:start_time])

      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "get_current_datetime", "input" => {} }] }
        when 2
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 3
          { "content" => [{ "type" => "tool_use", "id" => "t3", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => target_slot[:id] } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Your appointment is booked for 1:00 PM on #{target_slot[:start_time]}." }] }
        end
      end

      result = service.process_message(
        message: "Book me for 1pm",
        user: user,
        context_type: "scheduling"
      )

      expect(result[:message]).to include("booked")

      session = Session.where(client_id: client_record.id, status: "scheduled").last
      expect(session).to be_present
      expect(session.session_date).to be_within(1.second).of(expected_utc)
      expect(session.session_date.in_time_zone(zone).hour).to eq(13)
      expect(session.session_date.in_time_zone(zone).min).to eq(0)
    end
  end
end
