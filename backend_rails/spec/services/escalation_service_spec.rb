# frozen_string_literal: true

require "rails_helper"

RSpec.describe EscalationService do
  describe ".escalate" do
    let(:conversation) { create(:conversation) }

    it "escalates on crisis detection" do
      result = described_class.escalate(
        conversation: conversation,
        reason: "crisis_language",
        risk_level: "crisis"
      )

      expect(result[:escalated]).to be true
      expect(result[:conversation_id]).to eq(conversation.uuid)
    end

    it "pauses conversation after escalation" do
      described_class.escalate(
        conversation: conversation,
        reason: "crisis_language",
        risk_level: "crisis"
      )

      conversation.reload
      expect(conversation.status).to eq("paused")
    end

    it "logs escalation without PII" do
      allow(Rails.logger).to receive(:info)

      described_class.escalate(
        conversation: conversation,
        reason: "crisis_language",
        risk_level: "crisis"
      )

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/conversation_id=#{conversation.uuid}/)
      ).at_least(:once)

      # Verify no PII: user name/email should not appear in log messages
      expect(Rails.logger).to have_received(:info).twice # escalate + alert_staff
      expect(Rails.logger).not_to have_received(:info).with(
        a_string_matching(/#{Regexp.escape(conversation.user.email)}/)
      )
      expect(Rails.logger).not_to have_received(:info).with(
        a_string_matching(/#{Regexp.escape(conversation.user.name)}/)
      )
    end
  end

  describe ".check_accumulated_risk" do
    let(:conversation) { create(:conversation) }

    it "escalates on accumulated medium risk (3+ consecutive turns)" do
      progress = conversation.onboarding
      progress.medium_risk_count = 3
      conversation.save_onboarding!(progress)

      result = described_class.check_accumulated_risk(conversation: conversation)

      expect(result).to be true
      conversation.reload
      expect(conversation.status).to eq("paused")
    end

    it "does not escalate low-risk conversations" do
      progress = conversation.onboarding
      progress.medium_risk_count = 0
      conversation.save_onboarding!(progress)

      result = described_class.check_accumulated_risk(conversation: conversation)

      expect(result).to be false
      conversation.reload
      expect(conversation.status).to eq("active")
    end

    it "does not escalate when medium risk count is below threshold" do
      progress = conversation.onboarding
      progress.medium_risk_count = 2
      conversation.save_onboarding!(progress)

      result = described_class.check_accumulated_risk(conversation: conversation)

      expect(result).to be false
      conversation.reload
      expect(conversation.status).to eq("active")
    end
  end

  describe "integration with AgentService" do
    let(:mock_llm) { instance_double(LlmService) }
    let(:agent) { AgentService.new(llm_service: mock_llm) }
    let(:user) { create(:user, :client) }

    it "returns holding message for paused conversations" do
      conversation = create(:conversation, user: user, status: "paused")

      result = agent.process_message(
        message: "Hello",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "general"
      )

      expect(result[:message]).to include("on hold")
      expect(result[:message]).to include("988")
    end

    it "resets medium_risk_count on unflagged (low-risk) input" do
      allow(mock_llm).to receive(:call).and_return(
        "content" => [{ "type" => "text", "text" => "Hello!" }]
      )

      conversation = create(:conversation, user: user)
      progress = conversation.onboarding
      progress.medium_risk_count = 2
      conversation.save_onboarding!(progress)

      agent.process_message(
        message: "Hello, how are you?",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "general"
      )

      conversation.reload
      expect(conversation.onboarding.medium_risk_count).to eq(0)
    end
  end
end
