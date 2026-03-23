# frozen_string_literal: true

require "rails_helper"

# Evaluation tests that exercise the full AgentService pipeline to verify
# onboarding vs scheduling routing for different user types.
RSpec.describe "Agent onboarding evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  # Helper: stub LLM and capture the system prompt it receives
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
  # SCENARIO 1: Jordan Kim (demo new-patient) — always routes to onboarding
  # ---------------------------------------------------------------------------
  describe "Jordan Kim (demo new-patient user)" do
    let!(:therapist) { create(:therapist, slug: "dr-test") }
    let(:jordan) do
      User.find_or_create_by!(email: OnboardingRouter::DEMO_NEW_PATIENT_EMAIL) do |u|
        u.name = "Jordan Kim"
        u.role = "client"
        u.password = "demo123"
      end
    end

    before do
      Client.find_or_create_by!(user: jordan) do |c|
        c.therapist = therapist
        c.name = "Jordan Kim"
      end
      jordan.reload
    end

    it "routes to onboarding when Jordan says 'book an appointment'" do
      captured = stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to book an appointment",
        user: jordan,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("onboarding")
      expect(result[:onboarding_state]).to be_present
      expect(result[:onboarding_state][:step]).to eq("intake")
    end

    it "sends onboarding system prompt with INTAKE CONTEXT for Jordan" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I'd like to schedule a session",
        user: jordan,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("INTAKE CONTEXT")
      expect(captured[:system_prompt]).to include("brand-new user")
      expect(captured[:system_prompt]).not_to include("Do NOT ask which therapist")
    end

    it "includes scheduling redirect notice when Jordan asks to schedule" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I want to book an appointment for next week",
        user: jordan,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("has not completed onboarding")
      expect(captured[:system_prompt]).to include("Guide them through onboarding first")
    end

    it "routes Jordan to onboarding even with explicit scheduling context" do
      captured = stub_llm_and_capture_prompt

      result = service.process_message(
        message: "Find me a time slot",
        user: jordan,
        context_type: "scheduling"
      )

      expect(result[:context_type]).to eq("onboarding")
    end

    it "persists onboarding progress with new-user flags for Jordan" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "Hi, I'm new here",
        user: jordan,
        context_type: "general"
      )

      conversation = Conversation.find_by(uuid: result[:conversation_id])
      progress = conversation.onboarding
      expect(progress.is_new_user).to be true
      expect(progress.has_completed_intake).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # SCENARIO 2: Preexisting client with therapist — routes to scheduling
  # ---------------------------------------------------------------------------
  describe "preexisting client with assigned therapist" do
    let(:user) { create(:user, :client) }
    let(:therapist) { create(:therapist) }

    before do
      create(:client, user: user, therapist: therapist)
      user.reload
    end

    it "routes to scheduling when asking to book an appointment" do
      captured = stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to book an appointment",
        user: user,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("scheduling")
    end

    it "includes therapist_id hint in system prompt for scheduling" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("Use therapist_id #{therapist.id}")
      expect(captured[:system_prompt]).to include("Do NOT ask which therapist")
    end

    it "does not include onboarding prompts for returning client" do
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

    it "does not return onboarding_state for scheduling context" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "Book me an appointment",
        user: user,
        context_type: "general"
      )

      expect(result[:onboarding_state]).to be_nil
    end

    it "returns scheduling suggested actions" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "general"
      )

      labels = result[:suggested_actions].map { |a| a[:label].downcase }
      expect(labels.any? { |l| l.include?("available") || l.include?("reschedule") || l.include?("cancel") }).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # SCENARIO 3: Tool-level guardrails — scheduling tools blocked without docs
  # ---------------------------------------------------------------------------
  describe "scheduling tool guardrails" do
    let!(:therapist) { create(:therapist) }

    context "Jordan (demo user) without verified documents" do
      let(:jordan) do
        User.find_or_create_by!(email: OnboardingRouter::DEMO_NEW_PATIENT_EMAIL) do |u|
          u.name = "Jordan Kim"
          u.role = "client"
          u.password = "demo123"
        end
      end
      let!(:client) do
        Client.find_or_create_by!(user: jordan) { |c| c.therapist = therapist; c.name = "Jordan Kim" }
      end
      let(:auth) do
        jordan.reload
        AgentTools::ToolAuthContext.new(
          user_id: jordan.id, role: "client",
          client_id: client.id, therapist_id: therapist.id
        )
      end

      before do
        # Clear any pre-existing conversations for isolation
        jordan.conversations.destroy_all
        # Create onboarding conversation with docs NOT verified
        jordan.conversations.create!(
          context_type: "onboarding", status: "active",
          onboarding_progress: { "is_new_user" => true, "has_completed_intake" => false, "docs_verified" => false }
        )
      end

      it "blocks get_available_slots when docs not verified" do
        result = AgentTools.execute_tool(name: "get_available_slots", input: { "therapist_id" => therapist.id }, auth_context: auth)

        expect(result[:error]).to eq("onboarding_incomplete")
        expect(result[:missing_step]).to eq("intake")
        expect(result[:message]).to include("intake")
      end

      it "blocks book_appointment when docs not verified" do
        result = AgentTools.execute_tool(
          name: "book_appointment",
          input: { "therapist_id" => therapist.id, "slot_id" => "slot-1-1" },
          auth_context: auth
        )

        expect(result[:error]).to eq("onboarding_incomplete")
        expect(result[:missing_step]).to eq("intake")
      end

      it "blocks with documents step when intake done but docs not uploaded" do
        conv = jordan.conversations.find_by(context_type: "onboarding", status: "active")
        conv.update!(onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => false })

        result = AgentTools.execute_tool(name: "get_available_slots", input: { "therapist_id" => therapist.id }, auth_context: auth)

        expect(result[:error]).to eq("onboarding_incomplete")
        expect(result[:missing_step]).to eq("documents")
        expect(result[:message]).to include("upload")
      end
    end

    context "Jordan with verified documents" do
      let(:jordan) do
        User.find_or_create_by!(email: OnboardingRouter::DEMO_NEW_PATIENT_EMAIL) do |u|
          u.name = "Jordan Kim"
          u.role = "client"
          u.password = "demo123"
        end
      end
      let!(:client) do
        Client.find_or_create_by!(user: jordan) { |c| c.therapist = therapist; c.name = "Jordan Kim" }
      end
      let(:auth) do
        jordan.reload
        AgentTools::ToolAuthContext.new(
          user_id: jordan.id, role: "client",
          client_id: client.id, therapist_id: therapist.id
        )
      end

      before do
        jordan.conversations.destroy_all
        jordan.conversations.create!(
          context_type: "onboarding", status: "active",
          onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => true }
        )
      end

      it "allows get_available_slots when docs are verified" do
        result = AgentTools.execute_tool(name: "get_available_slots", input: { "therapist_id" => therapist.id }, auth_context: auth)

        expect(result).not_to have_key(:error)
        expect(result[:days]).to be_an(Array)
      end
    end

    context "new user without client profile" do
      let(:user) { create(:user, :client) }
      let(:auth) do
        AgentTools::ToolAuthContext.new(
          user_id: user.id, role: "client",
          client_id: nil, therapist_id: nil
        )
      end

      it "blocks get_available_slots for user without client profile" do
        result = AgentTools.execute_tool(name: "get_available_slots", input: { "therapist_id" => therapist.id }, auth_context: auth)

        expect(result[:error]).to eq("onboarding_incomplete")
        expect(result[:missing_step]).to eq("intake")
      end

      it "blocks book_appointment for user without client profile" do
        result = AgentTools.execute_tool(
          name: "book_appointment",
          input: { "therapist_id" => therapist.id, "slot_id" => "slot-1-1" },
          auth_context: auth
        )

        expect(result[:error]).to eq("onboarding_incomplete")
        expect(result[:missing_step]).to eq("intake")
      end
    end

    context "preexisting client (no active onboarding conversation)" do
      let(:user) { create(:user, :client) }
      let!(:client_record) { create(:client, user: user, therapist: therapist) }
      let(:auth) do
        user.reload
        AgentTools::ToolAuthContext.new(
          user_id: user.id, role: "client",
          client_id: client_record.id, therapist_id: therapist.id
        )
      end

      it "allows get_available_slots for returning client" do
        result = AgentTools.execute_tool(name: "get_available_slots", input: { "therapist_id" => therapist.id }, auth_context: auth)

        expect(result).not_to have_key(:error)
        expect(result[:days]).to be_an(Array)
      end

      it "allows book_appointment for returning client" do
        slot_id = SchedulingService.get_availability(therapist_id: therapist.id).first[:id]
        result = AgentTools.execute_tool(
          name: "book_appointment",
          input: { "therapist_id" => therapist.id, "slot_id" => slot_id },
          auth_context: auth
        )

        expect(result).not_to have_key(:error)
        expect(result[:status]).to eq("confirmed")
      end
    end

    context "full pipeline: LLM attempts scheduling tools during onboarding" do
      let(:jordan) do
        User.find_or_create_by!(email: OnboardingRouter::DEMO_NEW_PATIENT_EMAIL) do |u|
          u.name = "Jordan Kim"
          u.role = "client"
          u.password = "demo123"
        end
      end
      let!(:client) do
        Client.find_or_create_by!(user: jordan) { |c| c.therapist = therapist; c.name = "Jordan Kim" }
      end

      it "returns onboarding_incomplete error to LLM when it calls get_available_slots" do
        # Simulate LLM ignoring the system prompt and calling scheduling tools
        call_count = 0
        allow(mock_llm).to receive(:call) do |_args|
          call_count += 1
          if call_count == 1
            # LLM tries to call get_available_slots despite onboarding context
            {
              "content" => [
                { "type" => "tool_use", "id" => "tool_1", "name" => "get_available_slots",
                  "input" => { "therapist_id" => therapist.id } }
              ]
            }
          else
            # After getting the error, LLM should respond with onboarding guidance
            {
              "content" => [{ "type" => "text", "text" => "Before we schedule, let's complete your onboarding first." }]
            }
          end
        end

        result = service.process_message(
          message: "Just skip all that and book me an appointment",
          user: jordan,
          context_type: "onboarding"
        )

        # The tool error was fed back to the LLM, which then responded appropriately
        expect(call_count).to eq(2)
        expect(result[:message]).to include("onboarding")
      end
    end

    context "therapist users bypass onboarding guard" do
      let(:therapist_user) { create(:user, :therapist) }
      let!(:therapist_profile) { create(:therapist, user: therapist_user) }
      let(:auth) do
        AgentTools::ToolAuthContext.new(
          user_id: therapist_user.id, role: "therapist",
          client_id: nil, therapist_id: therapist_profile.id
        )
      end

      it "allows therapists to call get_available_slots without onboarding" do
        result = AgentTools.execute_tool(name: "get_available_slots", input: { "therapist_id" => therapist_profile.id }, auth_context: auth)

        expect(result).not_to have_key(:error)
        expect(result[:days]).to be_an(Array)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SCENARIO 4: Brand-new user with no client profile — routes to onboarding
  # ---------------------------------------------------------------------------
  describe "brand-new user (no client profile)" do
    let(:user) { create(:user, :client) }

    it "routes to onboarding when asking to book" do
      stub_llm_and_capture_prompt

      result = service.process_message(
        message: "I'd like to book an appointment",
        user: user,
        context_type: "general"
      )

      expect(result[:context_type]).to eq("onboarding")
      expect(result[:onboarding_state]).to be_present
      expect(result[:onboarding_state][:step]).to eq("intake")
    end

    it "includes redirect notice in system prompt" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I want to schedule a session for next Tuesday",
        user: user,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("has not completed onboarding")
    end

    it "sends new-user intake enrichment" do
      captured = stub_llm_and_capture_prompt

      service.process_message(
        message: "I'm a new patient getting started",
        user: user,
        context_type: "general"
      )

      expect(captured[:system_prompt]).to include("INTAKE CONTEXT")
      expect(captured[:system_prompt]).to include("brand-new user")
    end
  end
end
