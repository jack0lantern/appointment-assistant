# frozen_string_literal: true

require "rails_helper"

# Evaluation: Multi-turn tool chaining, round limits, and error recovery.
RSpec.describe "Multi-turn tool chaining evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  # ---------------------------------------------------------------------------
  # Sequential tool calls across rounds
  # ---------------------------------------------------------------------------
  describe "sequential tool calls across rounds" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "chains get_current_datetime → get_available_slots → book_appointment" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "get_current_datetime", "input" => {} }] }
        when 2
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 3
          slot_id = SchedulingService.get_availability(therapist_id: therapist.id).first[:id]
          { "content" => [{ "type" => "tool_use", "id" => "t3", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => slot_id } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Your appointment is confirmed for next week." }] }
        end
      end

      result = service.process_message(
        message: "I'd like to schedule an appointment for next week",
        user: user,
        context_type: "scheduling"
      )

      expect(call_count).to eq(4)
      expect(Session.where(client_id: client_record.id, status: "scheduled").count).to eq(1)
      expect(result[:message]).to include("confirmed")
    end

    it "chains search_therapists → confirm_therapist in sequence" do
      conversation = user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => true }
      )

      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          # Search without query to return all therapists
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "search_therapists",
            "input" => {} }] }
        when 2
          # Use the therapist's actual name for confirm
          display_label = therapist.user.name
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "confirm_therapist",
            "input" => { "display_label" => display_label } }] }
        else
          { "content" => [{ "type" => "text", "text" => "Great, I've confirmed your therapist selection." }] }
        end
      end

      result = service.process_message(
        message: "Help me find a therapist",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "onboarding"
      )

      expect(call_count).to eq(3)
      # therapist_results captured from search_therapists tool
      expect(result[:therapist_results]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # 5-round limit enforcement
  # ---------------------------------------------------------------------------
  describe "5-round limit enforcement" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "stops after MAX_TOOL_ROUNDS and returns fallback message" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        # Always return a tool_use, never text — force round exhaustion
        { "content" => [{ "type" => "tool_use", "id" => "t#{call_count}", "name" => "get_current_datetime", "input" => {} }] }
      end

      result = service.process_message(
        message: "What time is it?",
        user: user,
        context_type: "general"
      )

      expect(call_count).to eq(AgentService::MAX_TOOL_ROUNDS)
      expect(result[:message]).to include("wasn't able to complete")
    end

    it "returns last-captured therapist_results even at round limit" do
      conversation = user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => true }
      )

      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        case call_count
        when 1
          # Search without query to return all therapists
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "search_therapists",
            "input" => {} }] }
        else
          # Keep calling tools to exhaust rounds
          { "content" => [{ "type" => "tool_use", "id" => "t#{call_count}", "name" => "get_current_datetime", "input" => {} }] }
        end
      end

      result = service.process_message(
        message: "Find me a therapist",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "onboarding"
      )

      expect(call_count).to eq(AgentService::MAX_TOOL_ROUNDS)
      expect(result[:therapist_results]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Tool error recovery
  # ---------------------------------------------------------------------------
  describe "tool error recovery" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "feeds tool errors back to LLM for recovery" do
      call_count = 0
      tool_error_seen = false

      allow(mock_llm).to receive(:call) do |args|
        call_count += 1
        case call_count
        when 1
          # Call an unknown tool — will return an error result
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "nonexistent_scheduling_tool",
            "input" => {} }] }
        when 2
          # Check that error was fed back in the tool_result message
          last_msg = args[:messages].last
          if last_msg[:content].is_a?(Array)
            last_msg[:content].each do |tr|
              content_str = tr[:content].to_s
              if content_str.include?("Unknown tool") || content_str.include?("error")
                tool_error_seen = true
              end
            end
          end
          # Recover: get available slots properly
          { "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "get_available_slots",
            "input" => { "therapist_id" => therapist.id } }] }
        when 3
          slot_id = SchedulingService.get_availability(therapist_id: therapist.id).first[:id]
          { "content" => [{ "type" => "tool_use", "id" => "t3", "name" => "book_appointment",
            "input" => { "therapist_id" => therapist.id, "slot_id" => slot_id } }] }
        else
          { "content" => [{ "type" => "text", "text" => "I've booked your appointment." }] }
        end
      end

      result = service.process_message(
        message: "Book me an appointment",
        user: user,
        context_type: "scheduling"
      )

      expect(call_count).to eq(4)
      expect(tool_error_seen).to be(true)
      expect(Session.where(client_id: client_record.id, status: "scheduled").count).to eq(1)
    end

    it "handles unknown tool name gracefully" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        if call_count == 1
          { "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "nonexistent_tool", "input" => {} }] }
        else
          { "content" => [{ "type" => "text", "text" => "Let me try a different approach." }] }
        end
      end

      result = service.process_message(
        message: "Do something",
        user: user,
        context_type: "general"
      )

      expect(call_count).to eq(2)
      expect(result[:message]).to include("different approach")
    end
  end

  # ---------------------------------------------------------------------------
  # Parallel tool calls in single round
  # ---------------------------------------------------------------------------
  describe "parallel tool calls in single round" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    before { user.reload }

    it "executes multiple tool_use blocks in one LLM response" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |args|
        call_count += 1
        if call_count == 1
          {
            "content" => [
              { "type" => "tool_use", "id" => "t1", "name" => "get_current_datetime", "input" => {} },
              { "type" => "tool_use", "id" => "t2", "name" => "get_available_slots",
                "input" => { "therapist_id" => therapist.id } }
            ]
          }
        else
          # Check that both tool results were fed back
          last_msg = args[:messages].last
          expect(last_msg[:content]).to be_an(Array)
          expect(last_msg[:content].length).to eq(2)
          { "content" => [{ "type" => "text", "text" => "Here are your available times." }] }
        end
      end

      result = service.process_message(
        message: "What times are available?",
        user: user,
        context_type: "scheduling"
      )

      expect(call_count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # set_suggested_actions with text (early return)
  # ---------------------------------------------------------------------------
  describe "set_suggested_actions early return" do
    let(:user) { create(:user, :client) }

    it "returns immediately when text + set_suggested_actions in same response" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        {
          "content" => [
            { "type" => "text", "text" => "What brings you to therapy today?" },
            { "type" => "tool_use", "id" => "t1", "name" => "set_suggested_actions",
              "input" => { "actions" => [
                { "label" => "Anxiety", "payload" => "I'm dealing with anxiety" },
                { "label" => "Depression", "payload" => "I'm dealing with depression" },
                { "label" => "Relationships", "payload" => "I'm having relationship challenges" }
              ] } }
          ]
        }
      end

      result = service.process_message(
        message: "I'm new here",
        user: user,
        context_type: "general"
      )

      expect(call_count).to eq(1)
      expect(result[:suggested_actions]).to be_present
      expect(result[:suggested_actions].length).to eq(3)
      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("Anxiety", "Depression", "Relationships")
    end

    it "captures suggested_actions mid-tool-loop" do
      call_count = 0
      allow(mock_llm).to receive(:call) do |_args|
        call_count += 1
        if call_count == 1
          {
            "content" => [
              { "type" => "tool_use", "id" => "t1", "name" => "get_current_datetime", "input" => {} },
              { "type" => "tool_use", "id" => "t2", "name" => "set_suggested_actions",
                "input" => { "actions" => [
                  { "label" => "Morning", "payload" => "I prefer morning" },
                  { "label" => "Afternoon", "payload" => "I prefer afternoon" }
                ] } }
            ]
          }
        else
          { "content" => [{ "type" => "text", "text" => "Here are your options." }] }
        end
      end

      result = service.process_message(
        message: "When can I come in?",
        user: user,
        context_type: "general"
      )

      expect(result[:suggested_actions]).to be_present
      labels = result[:suggested_actions].map { |a| a[:label] }
      expect(labels).to include("Morning", "Afternoon")
    end
  end
end
