# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding Journey", type: :request do
  let(:mock_llm) { instance_double(LlmService) }
  let(:agent) { AgentService.new(llm_service: mock_llm) }

  before do
    allow(mock_llm).to receive(:call).and_return({
      "content" => [{ "type" => "text", "text" => "Welcome! Let's get you started with your onboarding." }]
    })
  end

  describe "full new user onboarding journey" do
    it "completes full new user onboarding journey" do
      # Create a user with no Client profile
      user = create(:user, :client)

      # Send message via the agent service — "I'm new here" matches ONBOARDING_KEYWORDS
      result = agent.process_message(
        message: "I'm new here",
        user: user,
        context_type: "general"
      )

      # Verify the response contains a message
      expect(result[:message]).to be_present

      # Verify conversation was created
      expect(result[:conversation_id]).to be_present

      # Verify context_type is "onboarding" (OnboardingRouter routes new users to onboarding)
      expect(result[:context_type]).to eq("onboarding")

      # Verify onboarding_state step is "intake" (new user, no intake completed)
      expect(result[:onboarding_state]).to be_present
      expect(result[:onboarding_state][:step]).to eq("intake")

      # Verify the conversation is persisted in the database
      conversation = user.conversations.find_by(uuid: result[:conversation_id])
      expect(conversation).to be_present
      expect(conversation.context_type).to eq("onboarding")

      # Verify onboarding_progress is persisted on conversation
      progress = conversation.onboarding
      expect(progress.is_new_user).to be true
      expect(progress.has_completed_intake).to be false

      # Verify the LLM was called (not short-circuited)
      expect(mock_llm).to have_received(:call).at_least(:once)
    end
  end

  describe "returning user with therapist" do
    it "handles returning user with therapist" do
      # Create a user with a Client profile that has a therapist assigned
      therapist = create(:therapist)
      user = create(:user, :client)
      client = create(:client, user: user, therapist: therapist)

      allow(mock_llm).to receive(:call).and_return({
        "content" => [{ "type" => "text", "text" => "Let me help you schedule an appointment." }]
      })

      # Send a scheduling-intent message
      result = agent.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      # Verify context_type is "scheduling" (not onboarding, since user has therapist)
      expect(result[:context_type]).to eq("scheduling")

      # Verify suggested actions include scheduling-related actions
      action_labels = result[:suggested_actions].map { |a| a[:label] }
      expect(action_labels).to include(a_string_matching(/available|schedule|reschedule|cancel/i))

      # Verify the LLM was called
      expect(mock_llm).to have_received(:call).at_least(:once)
    end
  end

  describe "crisis escalation during onboarding" do
    it "escalates crisis during onboarding" do
      user = create(:user, :client)

      # Start an onboarding conversation first
      initial_result = agent.process_message(
        message: "I'm new here",
        user: user,
        context_type: "general"
      )
      conversation_id = initial_result[:conversation_id]

      # Record how many times LLM was called during the initial message
      initial_call_count = mock_llm.as_null_object # not needed, count below
      # We track call count by counting received messages
      llm_call_count_before = 0
      allow(mock_llm).to receive(:call) do
        llm_call_count_before += 1
        { "content" => [{ "type" => "text", "text" => "This should not appear" }] }
      end

      # Reset the counter — any calls from here are for the crisis message
      llm_call_count_before = 0

      # Send a crisis message
      crisis_result = agent.process_message(
        message: "I don't want to be alive anymore",
        user: user,
        conversation_id: conversation_id,
        context_type: "onboarding"
      )

      # Verify response contains crisis resources (988 Lifeline)
      expect(crisis_result[:message]).to include("988")
      expect(crisis_result[:message]).to include("Crisis")

      # Verify safety.escalated is true
      expect(crisis_result[:safety][:flagged]).to be true
      expect(crisis_result[:safety][:flag_type]).to eq("crisis")
      expect(crisis_result[:safety][:escalated]).to be true

      # Verify LLM was NOT called for the crisis message (crisis short-circuits)
      expect(llm_call_count_before).to eq(0)

      # Verify the response matches known crisis response content
      expect(crisis_result[:message]).to include("Suicide & Crisis Lifeline")
      expect(crisis_result[:message]).to include("741741")
    end
  end

  describe "deep link with valid slug" do
    it "handles deep link with valid slug" do
      # Create a therapist with a known slug
      therapist_user = create(:user, :therapist, name: "Dr. Smith")
      therapist = create(:therapist, user: therapist_user, slug: "dr-smith")
      user = create(:user, :client)

      # Authenticated GET /api/onboard/dr-smith
      get "/api/onboard/dr-smith", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)

      # Verify response includes conversation_id and therapist_name
      expect(body["conversation_id"]).to be_present
      expect(body["therapist_name"]).to eq("Dr. Smith")
      expect(body["context_type"]).to eq("onboarding")

      # Verify conversation's onboarding_progress has assigned_therapist_id set
      conversation = user.conversations.find_by(uuid: body["conversation_id"])
      expect(conversation).to be_present
      progress = conversation.onboarding
      expect(progress.assigned_therapist_id).to eq(therapist.id)

      # Send a follow-up message using the conversation_id
      allow(mock_llm).to receive(:call).and_return({
        "content" => [{ "type" => "text", "text" => "Great! You're connected with Dr. Smith." }]
      })

      follow_up_result = agent.process_message(
        message: "What should I expect?",
        user: user,
        conversation_id: body["conversation_id"],
        context_type: "onboarding"
      )

      expect(follow_up_result[:message]).to be_present
      expect(follow_up_result[:conversation_id]).to eq(body["conversation_id"])
    end
  end

  describe "phantom booking during scheduling" do
    before(:each) { SchedulingService.clear_booked_slots! }

    it "handles phantom booking during scheduling" do
      # Create therapist + client
      therapist = create(:therapist)
      user = create(:user, :client)
      client = create(:client, user: user, therapist: therapist)

      # Book a slot via SchedulingService (marks it as taken)
      slot_id = "slot-#{therapist.id}-1"
      SchedulingService.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id,
        session_date: 1.day.from_now
      )

      # Try to book the same slot via AgentTools
      auth_context = AgentTools::ToolAuthContext.new(
        user_id: user.id,
        role: "client",
        client_id: client.id,
        therapist_id: therapist.id
      )

      result = AgentTools.execute_tool(
        name: "book_appointment",
        input: { "therapist_id" => therapist.id, "slot_id" => slot_id },
        auth_context: auth_context
      )

      # Verify the response includes conflict error with fresh slots
      expect(result[:error]).to eq("slot_conflict")
      expect(result[:message]).to include("just booked")
      expect(result[:available_slots]).to be_present
      expect(result[:available_slots]).to be_an(Array)
      expect(result[:available_slots].length).to be > 0
    end
  end
end
