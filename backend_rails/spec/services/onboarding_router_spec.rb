# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingRouter do
  describe ".route" do
    context "new users" do
      let(:user) { create(:user, :client) }
      let(:conversation) { create(:conversation, user: user, context_type: "onboarding") }

      it "routes new users to intake" do
        # User has no Client record
        expect(user.client_profile).to be_nil

        result = described_class.route(user: user, conversation: conversation)

        expect(result[:context_type]).to eq("onboarding")
        expect(result[:onboarding_progress].is_new_user).to be true
        expect(result[:onboarding_progress].has_completed_intake).to be false
      end
    end

    context "returning users without therapist" do
      let(:user) { create(:user, :client) }
      let(:conversation) { create(:conversation, user: user, context_type: "onboarding") }

      it "routes returning users without therapist to search" do
        # Client exists but therapist_id is nil (simulated via stub since DB has NOT NULL)
        therapist = create(:therapist)
        client = create(:client, user: user, therapist: therapist)
        user.reload

        # Simulate the "no therapist" state by stubbing therapist_id to nil
        allow(client).to receive(:therapist_id).and_return(nil)
        allow(user).to receive(:client_profile).and_return(client)

        result = described_class.route(user: user, conversation: conversation)

        expect(result[:context_type]).to eq("onboarding")
        expect(result[:onboarding_progress].is_new_user).to be false
        expect(result[:onboarding_progress].has_completed_intake).to be true
      end
    end

    context "returning users with therapist" do
      let(:user) { create(:user, :client) }
      let(:conversation) { create(:conversation, user: user, context_type: "onboarding") }

      it "routes returning users with therapist to scheduling" do
        therapist = create(:therapist)
        create(:client, user: user, therapist: therapist)
        user.reload

        result = described_class.route(user: user, conversation: conversation)

        expect(result[:context_type]).to eq("scheduling")
        expect(result[:onboarding_progress].is_new_user).to be false
        expect(result[:onboarding_progress].has_completed_intake).to be true
        expect(result[:onboarding_progress].assigned_therapist_id).to eq(therapist.id)
      end
    end

    context "persistence" do
      let(:user) { create(:user, :client) }
      let(:conversation) { create(:conversation, user: user, context_type: "onboarding") }

      it "persists onboarding progress across turns" do
        # First turn: new user
        described_class.route(user: user, conversation: conversation)
        conversation.reload

        stored = conversation.onboarding
        expect(stored.is_new_user).to be true

        # Verify raw JSONB persisted correctly
        expect(conversation.onboarding_progress).to be_a(Hash)
        expect(conversation.onboarding_progress["is_new_user"]).to be true
      end
    end

    context "prompt enrichment" do
      it "enriches system prompt for intake flow" do
        user = create(:user, :client)
        conversation = create(:conversation, user: user, context_type: "onboarding")

        routing = described_class.route(user: user, conversation: conversation)

        ctx = ContextBuilder.build(
          context_type: routing[:context_type],
          redacted_message: "I'm new here",
          onboarding_state: routing[:onboarding_progress]
        )

        expect(ctx[:system_prompt]).to include("INTAKE CONTEXT")
        expect(ctx[:system_prompt]).to include("brand-new user")
      end

      it "enriches system prompt for therapist search" do
        user = create(:user, :client)
        therapist = create(:therapist)
        client = create(:client, user: user, therapist: therapist)
        user.reload

        # Simulate no-therapist state
        allow(client).to receive(:therapist_id).and_return(nil)
        allow(user).to receive(:client_profile).and_return(client)

        conversation = create(:conversation, user: user, context_type: "onboarding")
        routing = described_class.route(user: user, conversation: conversation)

        ctx = ContextBuilder.build(
          context_type: routing[:context_type],
          redacted_message: "I need a therapist",
          onboarding_state: routing[:onboarding_progress]
        )

        expect(ctx[:system_prompt]).to include("THERAPIST SEARCH NEEDED")
      end

      it "enriches system prompt for assigned therapist" do
        user = create(:user, :client)
        therapist = create(:therapist)
        create(:client, user: user, therapist: therapist)
        user.reload

        # Manually construct onboarding state with assigned therapist
        progress = OnboardingProgress.new(
          is_new_user: false,
          has_completed_intake: true,
          assigned_therapist_id: therapist.id
        )

        ctx = ContextBuilder.build(
          context_type: "onboarding",
          redacted_message: "What's next?",
          onboarding_state: progress
        )

        expect(ctx[:system_prompt]).to include("THERAPIST ASSIGNED")
        expect(ctx[:system_prompt]).to include(therapist.id.to_s)
      end
    end
  end

  describe "paused conversation blocking" do
    let(:mock_llm) { instance_double(LlmService) }
    let(:service) { AgentService.new(llm_service: mock_llm) }
    let(:user) { create(:user, :client) }

    it "blocks messages for paused conversations" do
      conversation = create(:conversation, :paused, user: user)

      expect(mock_llm).not_to receive(:call)

      result = service.process_message(
        message: "Hello",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "general"
      )

      expect(result[:message]).to include("on hold")
      expect(result[:message]).to include("988")
    end
  end

  describe "risk_level persistence" do
    let(:mock_llm) { instance_double(LlmService) }
    let(:service) { AgentService.new(llm_service: mock_llm) }
    let(:user) { create(:user, :client) }

    it "persists risk_level from safety check" do
      result = service.process_message(
        message: "I want to kill myself",
        user: user,
        context_type: "general"
      )

      # The crisis message was handled; find the conversation
      conversation = user.conversations.last
      conversation.reload

      expect(conversation.onboarding.risk_level).to eq("crisis")
    end
  end
end
