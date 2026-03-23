# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentService do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { described_class.new(llm_service: mock_llm) }

  # Helper: stub LLM to return a simple text response (no tool calls)
  def stub_llm_text_response(text)
    allow(mock_llm).to receive(:call).and_return(
      "content" => [{ "type" => "text", "text" => text }]
    )
  end

  describe "#process_message" do
    context "redaction before LLM" do
      let(:user) { create(:user, :client) }

      it "restores PII tokens in agent response so user sees their actual email" do
        # User provides email; LLM sees [EMAIL_1] and may echo it back in response
        stub_llm_text_response("I've noted your email [EMAIL_1]. We'll send a confirmation there.")

        result = service.process_message(
          message: "My name is Jane and my email is jane@example.com",
          user: user,
          context_type: "general"
        )

        expect(result[:message]).to include("jane@example.com")
        expect(result[:message]).not_to include("[EMAIL_1]")
      end

      it "redacts PII from user message before sending to LLM" do
        stub_llm_text_response("Hello! How can I help?")

        # We spy on the LLM call to verify the message is redacted
        expect(mock_llm).to receive(:call) do |args|
          user_messages = args[:messages].select { |m| m[:role] == "user" }
          last_user_msg = user_messages.last[:content]
          expect(last_user_msg).not_to include("John Smith")
          expect(last_user_msg).not_to include("john@test.com")

          { "content" => [{ "type" => "text", "text" => "Hello!" }] }
        end

        service.process_message(
          message: "My name is John Smith and my email is john@test.com",
          user: user,
          context_type: "general"
        )
      end
    end

    context "system prompt content" do
      let(:user) { create(:user, :client) }

      it "includes context-appropriate system prompt" do
        expect(mock_llm).to receive(:call) do |args|
          expect(args[:system_prompt].downcase).to include("onboarding")
          { "content" => [{ "type" => "text", "text" => "Welcome!" }] }
        end

        service.process_message(
          message: "I'm a new patient and want to register",
          user: user,
          context_type: "general"
        )
      end
    end

    context "conversation history" do
      let(:user) { create(:user, :client) }

      it "includes prior messages in LLM call" do
        # Create a conversation with existing messages
        conversation = create(:conversation, user: user)
        conversation.messages.create!(role: "user", content: "Hi there")
        conversation.messages.create!(role: "assistant", content: "Hello! How can I help?")

        expect(mock_llm).to receive(:call) do |args|
          # Should have 2 history messages + 1 new user message
          expect(args[:messages].length).to be >= 3
          { "content" => [{ "type" => "text", "text" => "Sure thing!" }] }
        end

        service.process_message(
          message: "What services do you offer?",
          user: user,
          conversation_id: conversation.uuid,
          context_type: "general"
        )
      end
    end

    context "intent classification integration" do
      let(:user) { create(:user, :client) }

      it "classifies scheduling intent and uses scheduling context" do
        # Create a client profile so no onboarding redirect
        create(:client, user: user)
        user.reload

        expect(mock_llm).to receive(:call) do |args|
          expect(args[:system_prompt].downcase).to include("schedule")
          { "content" => [{ "type" => "text", "text" => "Let me find times." }] }
        end

        result = service.process_message(
          message: "I need to book an appointment for next Tuesday",
          user: user,
          context_type: "general"
        )

        expect(result[:context_type]).to eq("scheduling")
      end

      it "classifies emotional support intent" do
        stub_llm_text_response("I understand you're feeling overwhelmed.")

        result = service.process_message(
          message: "I'm feeling really overwhelmed and anxious right now",
          user: user,
          context_type: "general"
        )

        expect(result[:context_type]).to eq("emotional_support")
      end
    end

    context "suggested actions by context" do
      let(:user) { create(:user, :client) }

      it "returns scheduling-related actions for scheduling context" do
        create(:client, user: user)
        user.reload
        stub_llm_text_response("Here are your available times.")

        result = service.process_message(
          message: "I'd like to schedule an appointment",
          user: user,
          context_type: "general"
        )

        labels = result[:suggested_actions].map { |a| a[:label] }
        expect(labels.any? { |l| l.downcase.include?("appointment") || l.downcase.include?("available") || l.downcase.include?("schedule") }).to be true
      end

      it "returns onboarding-related actions for onboarding context" do
        stub_llm_text_response("Welcome! Let's get you started.")

        result = service.process_message(
          message: "I'm a new patient",
          user: user,
          context_type: "general"
        )

        labels = result[:suggested_actions].map { |a| a[:label] }
        expect(labels.any? { |l| l.downcase.include?("upload") || l.downcase.include?("start") || l.downcase.include?("document") }).to be true
      end
    end

    context "onboarding redirect for clients without profile" do
      let(:user) { create(:user, :client) }

      it "redirects scheduling to onboarding when client has no profile" do
        stub_llm_text_response("Let me help you get set up first.")

        result = service.process_message(
          message: "I'd like to book an appointment",
          user: user,
          context_type: "general"
        )

        expect(result[:context_type]).to eq("onboarding")
        labels = result[:suggested_actions].map { |a| a[:label] }
        expect(labels.any? { |l| l.downcase.include?("schedule") }).to be true
      end

      it "does not redirect when client has a profile" do
        create(:client, user: user)
        user.reload
        stub_llm_text_response("Here are your available times.")

        result = service.process_message(
          message: "I'd like to book an appointment",
          user: user,
          context_type: "general"
        )

        expect(result[:context_type]).to eq("scheduling")
      end

      it "does not redirect therapists" do
        therapist = create(:therapist, user: user)
        user.update!(role: "therapist")
        user.reload

        stub_llm_text_response("I can help schedule for your client.")

        result = service.process_message(
          message: "Book an appointment for my client",
          user: user,
          context_type: "general"
        )

        expect(result[:context_type]).to eq("scheduling")
      end

      it "includes therapist_id hint for onboarded client with assigned therapist" do
        therapist = create(:therapist)
        create(:client, user: user, therapist: therapist)
        user.reload

        expect(mock_llm).to receive(:call) do |args|
          expect(args[:system_prompt]).to include("Use therapist_id #{therapist.id}")
          expect(args[:system_prompt]).to include("Do NOT ask which therapist")
          { "content" => [{ "type" => "text", "text" => "Here are times." }] }
        end

        service.process_message(
          message: "I'd like to schedule an appointment",
          user: user,
          context_type: "general"
        )
      end
    end

    context "input safety crisis short-circuit" do
      let(:user) { create(:user, :client) }

      it "returns crisis response for crisis language" do
        result = service.process_message(
          message: "I want to kill myself",
          user: user,
          context_type: "general"
        )

        expect(result[:safety][:flagged]).to be true
        expect(result[:safety][:escalated]).to be true
        expect(result[:context_type]).to eq("emotional_support")
        expect(result[:message]).to include("988")
      end

      it "does not call LLM for crisis messages" do
        expect(mock_llm).not_to receive(:call)

        service.process_message(
          message: "I want to kill myself",
          user: user,
          context_type: "general"
        )
      end
    end

    context "response safety filtering" do
      let(:user) { create(:user, :client) }

      it "replaces response when flagged for clinical advice" do
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "You have depression and should take sertraline 50mg daily." }]
        )

        result = service.process_message(
          message: "What is wrong with me?",
          user: user,
          context_type: "general"
        )

        expect(result[:message]).to include("not able to provide medical advice")
        expect(result[:message]).not_to include("sertraline")
      end
    end

    context "conversation persistence" do
      let(:user) { create(:user, :client) }

      it "creates a conversation and saves messages" do
        stub_llm_text_response("Hello! How can I help?")

        expect {
          service.process_message(
            message: "Hello",
            user: user,
            context_type: "general"
          )
        }.to change(Conversation, :count).by(1)
          .and change(ConversationMessage, :count).by(2) # user + assistant
      end

      it "returns a conversation_id" do
        stub_llm_text_response("Hello!")

        result = service.process_message(
          message: "Hello",
          user: user,
          context_type: "general"
        )

        expect(result[:conversation_id]).to be_present
      end
    end

    context "disclaimer" do
      let(:user) { create(:user, :client) }

      it "appends disclaimer to all responses" do
        stub_llm_text_response("Here are some breathing exercises.")

        result = service.process_message(
          message: "Help me with anxiety",
          user: user,
          context_type: "general"
        )

        expect(result[:message]).to include("does not provide medical advice")
      end

      it "does not append disclaimer when LLM already included equivalent text (avoids duplication with therapist cards)" do
        llm_text = "Here are some therapists that might be a good fit.\n\n---\n*This is an AI assistant and does not provide medical advice, diagnoses, or treatment recommendations. Always consult a qualified healthcare provider for medical questions.*"
        stub_llm_text_response(llm_text)

        result = service.process_message(
          message: "I need a therapist for anxiety",
          user: user,
          context_type: "onboarding"
        )

        # Disclaimer should appear exactly once, not twice
        expect(result[:message].scan("does not provide medical advice").count).to eq(1)
      end
    end

    context "dynamic suggested actions from LLM" do
      let(:user) { create(:user, :client) }

      it "uses suggested_actions from set_suggested_actions tool when LLM presents options" do
        # LLM returns text + set_suggested_actions tool with options matching its response
        allow(mock_llm).to receive(:call).and_return(
          "content" => [
            { "type" => "text", "text" => "What brings you to therapy? For example, anxiety, depression, or relationship challenges?" },
            {
              "type" => "tool_use",
              "id" => "tool_sugg",
              "name" => "set_suggested_actions",
              "input" => {
                "actions" => [
                  { "label" => "Anxiety", "payload" => "I'm dealing with anxiety" },
                  { "label" => "Depression", "payload" => "I'm dealing with depression" },
                  { "label" => "Relationships", "payload" => "I'm dealing with relationship challenges" }
                ]
              }
            }
          ]
        )

        result = service.process_message(
          message: "I'm new and want to get started",
          user: user,
          context_type: "general"
        )

        labels = result[:suggested_actions].map { |a| a[:label] }
        expect(labels).to contain_exactly("Anxiety", "Depression", "Relationships")
        expect(result[:suggested_actions].map { |a| a[:payload] }).to contain_exactly(
          "I'm dealing with anxiety",
          "I'm dealing with depression",
          "I'm dealing with relationship challenges"
        )
      end
    end

    context "tool-calling loop" do
      let(:user) { create(:user, :client) }

      it "executes tools and feeds results back to LLM" do
        # First call returns a tool_use block
        first_response = {
          "content" => [
            { "type" => "tool_use", "id" => "tool_1", "name" => "get_current_datetime", "input" => {} }
          ]
        }
        # Second call returns text
        second_response = {
          "content" => [{ "type" => "text", "text" => "Today is Monday." }]
        }

        call_count = 0
        allow(mock_llm).to receive(:call) do
          call_count += 1
          call_count == 1 ? first_response : second_response
        end

        result = service.process_message(
          message: "What day is it?",
          user: user,
          context_type: "general"
        )

        expect(result[:message]).to include("Today is Monday.")
        expect(call_count).to eq(2)
      end
    end

    context "LLM error handling" do
      let(:user) { create(:user, :client) }

      it "returns a fallback message when LLM fails" do
        allow(mock_llm).to receive(:call).and_raise(StandardError, "API timeout")

        result = service.process_message(
          message: "Hello",
          user: user,
          context_type: "general"
        )

        expect(result[:message]).to include("having trouble processing")
      end
    end
  end
end
