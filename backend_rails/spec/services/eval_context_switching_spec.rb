# frozen_string_literal: true

require "rails_helper"

# Evaluation: Mid-conversation context type transitions.
RSpec.describe "Context switching evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

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
  # Scheduling → onboarding redirect for new user
  # ---------------------------------------------------------------------------
  describe "scheduling → onboarding redirect" do
    let(:user) { create(:user, :client) } # No client profile

    it "redirects scheduling to onboarding for new user" do
      captured = stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to book an appointment",
        user: user,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("onboarding")
      expect(result[:onboarding_state][:step]).to eq("intake")
    end

    it "appends 'I'm ready to schedule' button when redirected from scheduling" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("I'm ready to schedule")
    end

    it "system prompt includes redirect notice about incomplete onboarding" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I want to book an appointment for next week",
        user: user,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("has not completed onboarding")
      expect(captured[:system_prompt]).to include("Guide them through onboarding first")
    end
  end

  # ---------------------------------------------------------------------------
  # Context transitions across multiple messages
  # ---------------------------------------------------------------------------
  describe "general → emotional_support → scheduling" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "classifies emotional message and transitions context" do
      # Call 1: general context
      stub_llm_and_capture_prompt
      result1 = service.process_message(
        message: "Hello, I need some help",
        user: user,
        context_type: "general"
      )
      conversation_id = result1[:conversation_id]
      # "Hello, I need some help" should stay general (no scheduling/emotional keywords)
      expect(result1[:context_type]).to eq("general")

      # Call 2: emotional support (contains emotional keywords)
      result2 = service.process_message(
        message: "I'm feeling really overwhelmed and anxious right now",
        user: user,
        conversation_id: conversation_id,
        context_type: "general"
      )
      expect(result2[:context_type]).to eq("emotional_support")

      # Call 3: scheduling (contains scheduling keywords)
      result3 = service.process_message(
        message: "I'd like to book an appointment with my therapist",
        user: user,
        conversation_id: conversation_id,
        context_type: "general"
      )
      expect(result3[:context_type]).to eq("scheduling")
    end
  end

  # ---------------------------------------------------------------------------
  # Conversation context_type persistence
  # ---------------------------------------------------------------------------
  describe "conversation context_type persistence" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "updates conversation.context_type when context changes" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'm feeling really anxious and scared",
        user: user,
        context_type: "general"
      )

      conversation = Conversation.find_by(uuid: result[:conversation_id])
      expect(conversation.context_type).to eq("emotional_support")
    end
  end

  # ---------------------------------------------------------------------------
  # Onboarding complete → scheduling transition
  # ---------------------------------------------------------------------------
  describe "onboarding → scheduling after completion" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "transitions from onboarding to scheduling when onboarding complete" do
      stub_llm_and_capture_prompt

      # Start in onboarding with complete progress
      conversation = user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: {
          "is_new_user" => false,
          "has_completed_intake" => true,
          "docs_verified" => true,
          "assigned_therapist_id" => therapist.id
        }
      )

      # When user asks to schedule and routing detects completion, should go to scheduling
      result = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "onboarding"
      )

      # OnboardingRouter sees client with therapist → scheduling
      expect(result[:context_type]).to eq("scheduling")
    end
  end

  # ---------------------------------------------------------------------------
  # Document upload context
  # ---------------------------------------------------------------------------
  describe "document upload context detection" do
    let(:user) { create(:user, :client) }

    it "detects document_upload intent from upload-related message" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I want to upload my insurance card",
        user: user,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("document_upload")
    end
  end

  # ---------------------------------------------------------------------------
  # No redirect button for non-redirected flows
  # ---------------------------------------------------------------------------
  describe "redirect button not present when not redirected" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "does not append 'I'm ready to schedule' when not redirected" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).not_to include("I'm ready to schedule")
    end
  end
end
