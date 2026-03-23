require "rails_helper"

RSpec.describe ContextBuilder do
  describe ".build" do
    it "returns a hash with system_prompt and messages" do
      result = described_class.build(
        context_type: "general",
        redacted_message: "Hello"
      )
      expect(result).to have_key(:system_prompt)
      expect(result).to have_key(:messages)
    end

    it "includes shared rules in every system prompt" do
      IntentClassifier::CONTEXT_TYPES.each do |ctx|
        result = described_class.build(context_type: ctx, redacted_message: "Hi")
        prompt = result[:system_prompt]

        expect(prompt).to include("NEVER provide diagnoses"), "#{ctx} prompt missing diagnosis rule"
        expect(prompt).to include("988"), "#{ctx} prompt missing crisis hotline"
        expect(prompt).to include("personal identifying information"), "#{ctx} prompt missing PII rule"
      end
    end

    it "includes context-specific content in the system prompt" do
      result = described_class.build(context_type: "onboarding", redacted_message: "Hi")
      expect(result[:system_prompt].downcase).to include("onboarding")

      result = described_class.build(context_type: "scheduling", redacted_message: "Hi")
      expect(result[:system_prompt].downcase).to include("schedule")

      result = described_class.build(context_type: "emotional_support", redacted_message: "Hi")
      expect(result[:system_prompt].downcase).to include("distress")

      result = described_class.build(context_type: "document_upload", redacted_message: "Hi")
      expect(result[:system_prompt].downcase).to include("upload")
    end

    it "places the redacted message as the last user message" do
      result = described_class.build(
        context_type: "general",
        redacted_message: "I need help"
      )
      last_msg = result[:messages].last
      expect(last_msg[:role]).to eq("user")
      expect(last_msg[:content]).to eq("I need help")
    end

    it "includes conversation history before the new message" do
      history = [
        { role: "user", content: "Hi" },
        { role: "assistant", content: "Hello! How can I help?" }
      ]
      result = described_class.build(
        context_type: "general",
        redacted_message: "Book an appointment",
        history: history
      )
      expect(result[:messages].length).to eq(3)
      expect(result[:messages][0][:content]).to eq("Hi")
      expect(result[:messages][1][:content]).to eq("Hello! How can I help?")
      expect(result[:messages][2][:content]).to eq("Book an appointment")
    end

    it "appends onboarding redirect notice when redirected is true" do
      result = described_class.build(
        context_type: "onboarding",
        redacted_message: "I want to schedule",
        redirected: true
      )
      expect(result[:system_prompt]).to include("has not completed")
      expect(result[:system_prompt]).to include("onboarding")
      expect(result[:system_prompt]).to include("Do not call scheduling tools")
    end

    it "does not append redirect notice when redirected is false" do
      result = described_class.build(
        context_type: "onboarding",
        redacted_message: "I want to start",
        redirected: false
      )
      expect(result[:system_prompt]).not_to include("has not completed")
    end

    it "falls back to general prompt for unknown context type" do
      result = described_class.build(
        context_type: "unknown_type",
        redacted_message: "Hello"
      )
      expect(result[:system_prompt]).to include("supportive, empathetic AI assistant")
    end
  end

  describe ".suggested_actions" do
    it "returns actions for each known context type" do
      IntentClassifier::CONTEXT_TYPES.each do |ctx|
        actions = described_class.suggested_actions(ctx)
        expect(actions).to be_an(Array)
        expect(actions).not_to be_empty, "No actions for #{ctx}"
        actions.each do |a|
          expect(a).to have_key(:label)
          expect(a).to have_key(:payload)
        end
      end
    end

    it "returns scheduling-relevant actions for scheduling context" do
      actions = described_class.suggested_actions("scheduling")
      labels = actions.map { |a| a[:label].downcase }
      expect(labels).to include(a_string_matching(/appointment|schedule|available/))
    end

    it "returns onboarding-relevant actions for onboarding context" do
      actions = described_class.suggested_actions("onboarding")
      labels = actions.map { |a| a[:label].downcase }
      expect(labels).to include(a_string_matching(/upload|document|start|need/))
    end

    it "falls back to general actions for unknown context type" do
      actions = described_class.suggested_actions("unknown_type")
      expect(actions).to eq(described_class.suggested_actions("general"))
    end

    it "returns step-specific actions for onboarding when onboarding_state has step" do
      # therapist step: "Would you like me to help you find a therapist?" → possible next steps
      actions = described_class.suggested_actions("onboarding", { step: "therapist", docs_verified: true, therapist_selected: false })
      labels = actions.map { |a| a[:label].downcase }
      expect(labels).to include("yes, help me find a therapist")
      expect(labels).to include("tell me about specialties")
      expect(labels).not_to include("start onboarding")

      # documents step
      actions = described_class.suggested_actions("onboarding", { step: "documents", docs_verified: false, therapist_selected: false })
      labels = actions.map { |a| a[:label].downcase }
      expect(labels).to include("upload insurance card")
      expect(labels).to include("upload id")
    end

    it "falls back to generic onboarding when onboarding_state step is nil" do
      actions = described_class.suggested_actions("onboarding", { step: nil, docs_verified: false, therapist_selected: false })
      labels = actions.map { |a| a[:label].downcase }
      expect(labels).to include("start onboarding")
      expect(labels).to include("upload a document")
    end
  end
end
