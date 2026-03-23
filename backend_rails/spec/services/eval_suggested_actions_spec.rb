# frozen_string_literal: true

require "rails_helper"

# Evaluation: Suggested actions — context-based defaults, step-specific, LLM override, and crisis.
RSpec.describe "Suggested actions evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  def stub_llm_text(text = "OK, I can help with that.")
    allow(mock_llm).to receive(:call).and_return(
      "content" => [{ "type" => "text", "text" => text }]
    )
  end

  # ---------------------------------------------------------------------------
  # Context-based defaults from ContextBuilder
  # ---------------------------------------------------------------------------
  describe "context-based defaults" do
    it "returns general actions for general context" do
      actions = ContextBuilder.suggested_actions("general")
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Help me get started")
      expect(labels).to include("Schedule an appointment")
    end

    it "returns onboarding actions for onboarding context (no step)" do
      actions = ContextBuilder.suggested_actions("onboarding")
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Start onboarding")
    end

    it "returns scheduling actions for scheduling context" do
      actions = ContextBuilder.suggested_actions("scheduling")
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Find available times")
      expect(labels).to include("Cancel appointment")
    end

    it "returns emotional_support actions for emotional_support context" do
      actions = ContextBuilder.suggested_actions("emotional_support")
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Talk to someone now")
      expect(labels).to include("Breathing exercise")
    end

    it "returns document_upload actions for document_upload context" do
      actions = ContextBuilder.suggested_actions("document_upload")
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Upload insurance card")
      expect(labels).to include("Upload ID")
    end
  end

  # ---------------------------------------------------------------------------
  # Onboarding step-specific actions
  # ---------------------------------------------------------------------------
  describe "onboarding step-specific actions" do
    it "returns intake actions when step is 'intake'" do
      actions = ContextBuilder.suggested_actions("onboarding", { step: "intake" })
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Start onboarding")
      expect(labels).to include("What do I need?")
    end

    it "returns documents actions when step is 'documents'" do
      actions = ContextBuilder.suggested_actions("onboarding", { step: "documents" })
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Upload insurance card")
      expect(labels).to include("Upload ID")
    end

    it "returns therapist actions when step is 'therapist'" do
      actions = ContextBuilder.suggested_actions("onboarding", { step: "therapist" })
      labels = actions.map { |a| a[:label] }
      expect(labels.any? { |l| l.downcase.include?("therapist") }).to be true
    end

    it "returns schedule actions when step is 'schedule'" do
      actions = ContextBuilder.suggested_actions("onboarding", { step: "schedule" })
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Find available times")
    end

    it "returns complete actions when step is 'complete'" do
      actions = ContextBuilder.suggested_actions("onboarding", { step: "complete" })
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Find available times")
      expect(labels).to include("Reschedule")
    end
  end

  # ---------------------------------------------------------------------------
  # LLM-generated suggested actions override defaults
  # ---------------------------------------------------------------------------
  describe "LLM-generated suggested actions" do
    let(:user) { create(:user, :client) }

    it "uses LLM-provided actions from set_suggested_actions tool" do
      allow(mock_llm).to receive(:call).and_return(
        "content" => [
          { "type" => "text", "text" => "What brings you to therapy?" },
          { "type" => "tool_use", "id" => "t1", "name" => "set_suggested_actions",
            "input" => { "actions" => [
              { "label" => "Anxiety", "payload" => "anxiety" },
              { "label" => "Depression", "payload" => "depression" }
            ] } }
        ]
      )

      result = service.process_message(
        message: "Hi, I'm new",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to eq(["Anxiety", "Depression"])
    end

    it "falls back to context defaults when LLM does not call set_suggested_actions" do
      stub_llm_text("Welcome! How can I help you today?")

      result = service.process_message(
        message: "Hello",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("Help me get started")
    end
  end

  # ---------------------------------------------------------------------------
  # Tool-aware suggested actions (fallback between LLM and static defaults)
  # ---------------------------------------------------------------------------
  describe "tool-aware suggested actions" do
    it "returns confirm_therapist follow-ups after therapist selection" do
      actions = ContextBuilder.tool_aware_suggestions(["search_therapists", "confirm_therapist"])
      expect(actions).to be_present
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Book an appointment")
      expect(labels).to include("See available times")
    end

    it "returns booking follow-ups after book_appointment" do
      actions = ContextBuilder.tool_aware_suggestions(["get_available_slots", "book_appointment"])
      expect(actions).to be_present
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("View my appointments")
      expect(labels).to include("What to expect")
    end

    it "returns search follow-ups after search_therapists" do
      actions = ContextBuilder.tool_aware_suggestions(["search_therapists"])
      expect(actions).to be_present
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Help me choose")
    end

    it "returns upload follow-ups after upload_document" do
      actions = ContextBuilder.tool_aware_suggestions(["upload_document"])
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Upload another document")
      expect(labels).to include("What's next?")
    end

    it "returns slot follow-ups after get_available_slots" do
      actions = ContextBuilder.tool_aware_suggestions(["get_current_datetime", "get_available_slots"])
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Book one of these")
    end

    it "returns nil for unknown or utility-only tools" do
      expect(ContextBuilder.tool_aware_suggestions(["get_current_datetime"])).to be_nil
      expect(ContextBuilder.tool_aware_suggestions(["set_suggested_actions"])).to be_nil
    end

    it "returns nil for empty or nil tool lists" do
      expect(ContextBuilder.tool_aware_suggestions([])).to be_nil
      expect(ContextBuilder.tool_aware_suggestions(nil)).to be_nil
    end

    it "picks the last significant tool when multiple ran" do
      # confirm_therapist is last significant → should get therapist confirmation actions
      actions = ContextBuilder.tool_aware_suggestions(["search_therapists", "confirm_therapist"])
      labels = actions.map { |a| a[:label] }
      expect(labels).to include("Book an appointment")
      expect(labels).not_to include("Help me choose")
    end
  end

  # ---------------------------------------------------------------------------
  # Tool-aware integration: suggestions after tool execution in pipeline
  # ---------------------------------------------------------------------------
  describe "tool-aware pipeline integration" do
    let(:user) { create(:user, :client) }

    it "uses tool-aware suggestions when LLM runs confirm_therapist but not set_suggested_actions" do
      # Simulate: LLM calls confirm_therapist, then responds with text (no set_suggested_actions)
      call_count = 0
      allow(mock_llm).to receive(:call) do
        call_count += 1
        if call_count == 1
          # First call: LLM wants to confirm therapist
          { "content" => [
            { "type" => "tool_use", "id" => "t1", "name" => "confirm_therapist",
              "input" => { "therapist_id" => 999 } }
          ] }
        else
          # Second call: LLM responds with text (no set_suggested_actions)
          { "content" => [
            { "type" => "text", "text" => "Dr. Chen is now your therapist! Ready to book?" }
          ] }
        end
      end

      # Stub the tool execution to avoid DB lookup
      allow(AgentTools).to receive(:execute_tool).and_return({ success: true, therapist: { name: "Dr. Chen" } })

      result = service.process_message(
        message: "I'd like Dr. Chen",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("Book an appointment")
      expect(labels).to include("See available times")
      expect(labels).not_to include("Help me get started")
    end
  end

  # ---------------------------------------------------------------------------
  # Redirect button injection
  # ---------------------------------------------------------------------------
  describe "redirect button injection" do
    let(:user) { create(:user, :client) } # No client profile → redirect

    it "appends 'I'm ready to schedule' when redirected from scheduling" do
      stub_llm_text

      result = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("I'm ready to schedule")
    end
  end

  # ---------------------------------------------------------------------------
  # Crisis suggested actions
  # ---------------------------------------------------------------------------
  describe "crisis suggested actions" do
    let(:user) { create(:user, :client) }

    it "returns crisis-specific actions when input safety escalates" do
      result = service.process_message(
        message: "I want to kill myself",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("Schedule urgent session")
      expect(labels).to include("More resources")
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline integration: correct actions per flow
  # ---------------------------------------------------------------------------
  describe "pipeline integration" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "returns scheduling suggested actions for returning client" do
      stub_llm_text

      result = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels.any? { |l| l.downcase.include?("available") || l.downcase.include?("reschedule") || l.downcase.include?("cancel") }).to be true
    end

    it "returns onboarding step-specific actions for new user" do
      new_user = create(:user, :client)
      stub_llm_text

      result = service.process_message(
        message: "Hi, I'm new here",
        user: new_user,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("general").or eq("onboarding")
      # Should have actions relevant to the context
      expect(result[:suggested_actions]).to be_present
    end
  end
end
