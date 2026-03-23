# frozen_string_literal: true

require "rails_helper"

# Evaluation: Returning client cancel, rebook, and reschedule flows.
RSpec.describe "Returning client rebooking evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  let(:user) { create(:user, :client) }
  let!(:therapist) { create(:therapist) }
  let!(:client_record) { create(:client, user: user, therapist: therapist) }

  before { user.reload }

  def stub_llm_and_capture_prompt
    captured = {}
    allow(mock_llm).to receive(:call) do |args|
      captured[:system_prompt] = args[:system_prompt]
      captured[:messages] = args[:messages]
      { "content" => [{ "type" => "text", "text" => "OK, I can help with that." }] }
    end
    captured
  end

  # ---------------------------------------------------------------------------
  # Context routing for returning clients
  # ---------------------------------------------------------------------------
  describe "context routing" do
    it "routes directly to scheduling (no onboarding redirect)" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to book an appointment",
        user: user,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("scheduling")
    end

    it "includes therapist_id hint in system prompt" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("Use therapist_id #{therapist.id}")
      expect(captured[:system_prompt]).to include("Do NOT ask which therapist")
    end

    it "does not include onboarding prompts" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I want to schedule a session",
        user: user,
        context_type: "general"
      )

      expect(captured[:system_prompt]).not_to include("INTAKE CONTEXT")
      expect(captured[:system_prompt]).not_to include("brand-new user")
      expect(captured[:system_prompt]).not_to include("has not completed onboarding")
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel flow via list_appointments → cancel_appointment
  # ---------------------------------------------------------------------------
  describe "cancel flow" do
    let!(:scheduled_session) do
      Session.create!(
        therapist: therapist, client: client_record,
        session_date: 2.days.from_now, session_number: 1,
        duration_minutes: 50, status: "scheduled"
      )
    end

    it "LLM calls list_appointments then cancel_appointment" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "list_appointments", "input" => {} }] }
        when 2
          { "content" => [{ "type" => "text", "text" => "Here are your upcoming appointments. Which would you like to cancel?" }] }
        else
          { "content" => [{ "type" => "text", "text" => "Done." }] }
        end
      end

      result = service.process_message(
        message: "I need to cancel my appointment",
        user: user,
        context_type: "scheduling"
      )

      expect(call_count).to eq(2)
      expect(result[:appointment_results]).to be_present
      expect(result[:appointment_results].first[:session_id]).to eq(scheduled_session.id)
    end

    it "asks for confirmation when user selects appointment (does not cancel yet)" do
      allow(mock_llm).to receive(:call).and_return(
        "content" => [{ "type" => "text",
          "text" => "Are you sure you want to cancel your appointment on Tuesday at 3:00 PM? Please confirm." }]
      )

      result = service.process_message(
        message: "Cancel session #{scheduled_session.id}",
        user: user,
        context_type: "scheduling"
      )

      scheduled_session.reload
      expect(scheduled_session.status).to eq("scheduled")
      expect(result[:message]).to include("sure")
    end

    it "cancels appointment when user confirms" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "cancel_appointment",
            "input" => { "session_id" => scheduled_session.id } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Your appointment has been cancelled." }] }
        end
      end

      result = service.process_message(
        message: "Yes, please cancel session #{scheduled_session.id}",
        user: user,
        context_type: "scheduling"
      )

      scheduled_session.reload
      expect(scheduled_session.status).to eq("cancelled")
      expect(result[:message]).to include("cancelled")
    end

    it "handles empty appointment list gracefully" do
      # Remove the scheduled session
      scheduled_session.update!(status: "cancelled")

      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        if call_count == 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "list_appointments", "input" => {} }] }
        else
          { "content" => [{ "type" => "text", "text" => "You don't have any upcoming appointments to cancel." }] }
        end
      end

      result = service.process_message(
        message: "I want to cancel",
        user: user,
        context_type: "scheduling"
      )

      expect(call_count).to eq(2)
      expect(result[:message]).to include("don't have any")
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel + rebook flow
  # ---------------------------------------------------------------------------
  describe "cancel + rebook" do
    let!(:scheduled_session) do
      Session.create!(
        therapist: therapist, client: client_record,
        session_date: 2.days.from_now, session_number: 1,
        duration_minutes: 50, status: "scheduled"
      )
    end

    it "cancels existing session then books new one across separate messages" do
      # Message 1: Cancel
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "cancel_appointment",
            "input" => { "session_id" => scheduled_session.id } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Your appointment has been cancelled." }] }
        end
      end

      result1 = service.process_message(
        message: "Yes, cancel session #{scheduled_session.id}",
        user: user,
        context_type: "scheduling"
      )

      conversation_id = result1[:conversation_id]
      scheduled_session.reload
      expect(scheduled_session.status).to eq("cancelled")

      # Message 2: Rebook
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 2
          slot_id = SchedulingService.get_availability(therapist_id: therapist.id).first[:id]
          { "content" => [{ "type" => "tool_use", "id" => "t3", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => slot_id } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Your new appointment has been booked!" }] }
        end
      end

      result2 = service.process_message(
        message: "Now book me a new appointment",
        user: user,
        conversation_id: conversation_id,
        context_type: "scheduling"
      )

      expect(result2[:message]).to include("booked")
      new_session = Session.where(client_id: client_record.id, status: "scheduled").last
      expect(new_session).to be_present
      expect(new_session.id).not_to eq(scheduled_session.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Reschedule in a single multi-turn conversation
  # ---------------------------------------------------------------------------
  describe "reschedule (cancel + rebook in one message)" do
    let!(:scheduled_session) do
      Session.create!(
        therapist: therapist, client: client_record,
        session_date: 2.days.from_now, session_number: 1,
        duration_minutes: 50, status: "scheduled"
      )
    end

    it "LLM chains cancel then book tools in sequence within tool loop" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "list_appointments", "input" => {} }] }
        when 2
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "cancel_appointment",
            "input" => { "session_id" => scheduled_session.id } }] }
        when 3
          { "content" => [{ "type" => "tool_use", "id" => "t3", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 4
          slot_id = SchedulingService.get_availability(therapist_id: therapist.id).first[:id]
          { "content" => [{ "type" => "tool_use", "id" => "t4", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => slot_id } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Done! I've rescheduled your appointment." }] }
        end
      end

      result = service.process_message(
        message: "I need to reschedule my appointment",
        user: user,
        context_type: "scheduling"
      )

      expect(call_count).to eq(5)
      expect(call_count).to be <= AgentService::MAX_TOOL_ROUNDS + 1 # 5 rounds + final text at round 5
      scheduled_session.reload
      expect(scheduled_session.status).to eq("cancelled")
      new_session = Session.where(client_id: client_record.id, status: "scheduled").last
      expect(new_session).to be_present
    end
  end
end
