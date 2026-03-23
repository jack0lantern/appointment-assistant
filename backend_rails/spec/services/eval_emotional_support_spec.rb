# frozen_string_literal: true

require "rails_helper"

# Evaluation: Emotional support tools, crisis short-circuit, and medium-risk accumulation.
RSpec.describe "Emotional support & crisis evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  # ---------------------------------------------------------------------------
  # Grounding exercise tool via pipeline
  # ---------------------------------------------------------------------------
  describe "grounding exercise" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "LLM calls get_grounding_exercise and returns exercise content" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        if call_count == 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "get_grounding_exercise", "input" => {} }] }
        else
          { "content" => [{ "type" => "text", "text" => "Here's a breathing exercise to help you feel calmer." }] }
        end
      end

      result = service.process_message(
        message: "I'm feeling really anxious, can you help me calm down?",
        user: user,
        context_type: "emotional_support"
      )

      expect(call_count).to eq(2)
      expect(result[:message]).to include("breathing exercise")
    end
  end

  # ---------------------------------------------------------------------------
  # Psychoeducation tool
  # ---------------------------------------------------------------------------
  describe "psychoeducation" do
    let(:user) { create(:user, :client) }

    it "returns anxiety content for 'anxiety' topic" do
      auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)
      result = AgentTools.execute_tool(name: "get_psychoeducation", input: { "topic" => "anxiety" }, auth_context: auth)
      expect(result[:content]).to be_present
    end

    it "returns first_session content for 'first_session' topic" do
      auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)
      result = AgentTools.execute_tool(name: "get_psychoeducation", input: { "topic" => "first_session" }, auth_context: auth)
      expect(result[:content]).to be_present
    end

    it "returns therapy_general content for 'therapy_general' topic" do
      auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)
      result = AgentTools.execute_tool(name: "get_psychoeducation", input: { "topic" => "therapy_general" }, auth_context: auth)
      expect(result[:content]).to be_present
    end

    it "returns error for unknown topic" do
      auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)
      result = AgentTools.execute_tool(name: "get_psychoeducation", input: { "topic" => "quantum_physics" }, auth_context: auth)
      expect(result[:error]).to include("Unknown topic")
    end
  end

  # ---------------------------------------------------------------------------
  # Validation message tool
  # ---------------------------------------------------------------------------
  describe "validation message" do
    let(:user) { create(:user, :client) }

    it "returns warm validating message via get_validation_message tool" do
      auth = AgentTools::ToolAuthContext.new(user_id: user.id, role: "client", client_id: nil, therapist_id: nil)
      result = AgentTools.execute_tool(name: "get_validation_message", input: {}, auth_context: auth)
      expect(result[:message]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Crisis short-circuit
  # ---------------------------------------------------------------------------
  describe "crisis short-circuit" do
    let(:user) { create(:user, :client) }

    it "returns crisis response with 988 hotline for suicidal ideation" do
      result = service.process_message(
        message: "I want to kill myself",
        user: user,
        context_type: "general"
      )

      expect(result[:safety][:flagged]).to be true
      expect(result[:safety][:escalated]).to be true
      expect(result[:safety][:flag_type]).to eq("crisis")
      expect(result[:message]).to include("988")
      expect(result[:context_type]).to eq("emotional_support")
    end

    it "does NOT call LLM for crisis messages" do
      expect(mock_llm).not_to receive(:call)

      service.process_message(
        message: "I want to end my life",
        user: user,
        context_type: "general"
      )
    end

    it "returns crisis suggested actions" do
      result = service.process_message(
        message: "I don't want to be alive anymore",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("Schedule urgent session")
      expect(labels).to include("More resources")
    end

    it "saves user message to conversation even during crisis" do
      result = service.process_message(
        message: "I want to kill myself",
        user: user,
        context_type: "general"
      )

      conversation = Conversation.find_by(uuid: result[:conversation_id])
      messages = conversation.messages.order(:created_at)
      expect(messages.count).to eq(2)
      expect(messages.first.role).to eq("user")
      expect(messages.last.role).to eq("assistant")
    end

    it "handles self-harm language patterns" do
      result = service.process_message(
        message: "I've been cutting myself",
        user: user,
        context_type: "general"
      )

      expect(result[:safety][:escalated]).to be true
      expect(result[:message]).to include("988")
    end

    it "handles harm-to-others language patterns" do
      result = service.process_message(
        message: "I want to hurt someone",
        user: user,
        context_type: "general"
      )

      expect(result[:safety][:escalated]).to be true
      expect(result[:message]).to include("988")
    end
  end

  # ---------------------------------------------------------------------------
  # Medium-risk accumulation
  # ---------------------------------------------------------------------------
  describe "medium-risk accumulation" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    context "below threshold (< 3 consecutive medium-risk turns)" do
      it "tracks medium_risk_count but does not escalate" do
        allow_any_instance_of(InputSafetyService).to receive(:check).and_return(
          { flagged: true, flag_type: "medium", escalated: false }
        )
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "I hear you and want to help." }]
        )

        result = service.process_message(
          message: "I'm feeling really down lately",
          user: user,
          context_type: "general"
        )

        conversation = Conversation.find_by(uuid: result[:conversation_id])
        expect(conversation.onboarding.medium_risk_count).to eq(1)
        expect(conversation.status).to eq("active")
      end
    end

    context "at threshold (>= 3 consecutive medium-risk turns)" do
      it "auto-escalates and pauses conversation at 3rd medium-risk turn" do
        allow_any_instance_of(InputSafetyService).to receive(:check).and_return(
          { flagged: true, flag_type: "medium", escalated: false }
        )

        # Pre-create conversation with medium_risk_count at 2
        conversation = user.conversations.create!(
          context_type: "general", status: "active",
          onboarding_progress: { "medium_risk_count" => 2 }
        )

        result = service.process_message(
          message: "Things keep getting worse",
          user: user,
          conversation_id: conversation.uuid,
          context_type: "general"
        )

        expect(result[:safety][:escalated]).to be true
        expect(result[:safety][:flag_type]).to eq("medium")
        conversation.reload
        expect(conversation.status).to eq("paused")
        expect(result[:message]).to include("on hold")
      end
    end

    context "risk counter reset" do
      it "resets medium_risk_count when a low-risk message arrives" do
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "I can help with that." }]
        )

        conversation = user.conversations.create!(
          context_type: "general", status: "active",
          onboarding_progress: { "medium_risk_count" => 2 }
        )

        result = service.process_message(
          message: "What times are available this week?",
          user: user,
          conversation_id: conversation.uuid,
          context_type: "general"
        )

        conversation.reload
        expect(conversation.onboarding.medium_risk_count).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Paused conversation enforcement
  # ---------------------------------------------------------------------------
  describe "paused conversation" do
    let(:user) { create(:user, :client) }

    it "returns paused response for any message to a paused conversation" do
      conversation = user.conversations.create!(
        context_type: "general", status: "paused",
        onboarding_progress: { "medium_risk_count" => 3 }
      )

      expect(mock_llm).not_to receive(:call)

      result = service.process_message(
        message: "Hello, can you help me?",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "general"
      )

      expect(result[:message]).to include("on hold")
      expect(result[:message]).to include("988")
    end

    it "saves user message even for paused conversations" do
      conversation = user.conversations.create!(
        context_type: "general", status: "paused",
        onboarding_progress: {}
      )

      service.process_message(
        message: "I need help",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "general"
      )

      expect(conversation.messages.where(role: "user").count).to eq(1)
      expect(conversation.messages.where(role: "assistant").count).to eq(1)
    end
  end
end
