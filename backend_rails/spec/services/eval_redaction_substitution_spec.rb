# frozen_string_literal: true

require "rails_helper"

# Evaluation: Verify redaction tokens like [NAME_1] never appear in agent
# responses shown to the user during onboarding.
#
# Uses REAL LLM calls (no mocks) to confirm the full pipeline handles PII
# redaction and restoration correctly, including edge cases where the user's
# name is provided without a regex-matching prefix.
RSpec.describe "Redaction substitution evaluation", type: :service do
  let(:service) { AgentService.new } # real LLM — no mock

  # ---------------------------------------------------------------------------
  # EVAL-REDACT-1: Name with "My name is" prefix — redaction fires, restore works
  # ---------------------------------------------------------------------------
  describe "EVAL-REDACT-1: name with prefix is redacted and restored" do
    let(:user) { create(:user, :client) }

    it "restores [NAME_1] to the real name in the agent response" do
      result = service.process_message(
        message: "Hi, I'm a new patient. My name is Priya Ramanathan.",
        user: user,
        context_type: "onboarding"
      )

      expect(result[:message]).not_to include("[NAME_1]"),
        "Response must not contain raw [NAME_1] token — got: #{result[:message].truncate(300)}"
    end
  end

  # ---------------------------------------------------------------------------
  # EVAL-REDACT-2: Bare name without prefix — the actual reported bug scenario.
  # The agent asks "What's your name?" and the user replies with just their name.
  # NAME_RE won't match, so no redaction happens. The LLM must NOT fabricate
  # [NAME_1] tokens in its response.
  # ---------------------------------------------------------------------------
  describe "EVAL-REDACT-2: bare name without prefix does not produce tokens" do
    let(:user) { create(:user, :client) }

    it "does not output [NAME_1] when user replies with just their name" do
      # Turn 1: start onboarding
      result1 = service.process_message(
        message: "I'd like to schedule an appointment",
        user: user,
        context_type: "onboarding"
      )
      conversation_id = result1[:conversation_id]

      # Turn 2: reply with bare name (no "My name is" prefix)
      result2 = service.process_message(
        message: "Jordan Kim",
        user: user,
        conversation_id: conversation_id,
        context_type: "onboarding"
      )

      expect(result2[:message]).not_to include("[NAME_1]"),
        "Response must not contain [NAME_1] when user gives bare name — got: #{result2[:message].truncate(300)}"
      expect(result2[:message]).not_to match(/\[NAME_\d+\]/),
        "Response must not contain any NAME tokens — got: #{result2[:message].truncate(300)}"
      expect(result2[:message]).to include("Jordan"),
        "Response should address the user by name — got: #{result2[:message].truncate(300)}"
    end
  end

  # ---------------------------------------------------------------------------
  # EVAL-REDACT-3: Multi-turn — name from turn 1 is restored in turn 2
  # ---------------------------------------------------------------------------
  describe "EVAL-REDACT-3: cross-turn name restoration" do
    let(:user) { create(:user, :client) }

    it "restores name provided in an earlier turn when LLM echoes the token" do
      # Turn 1: provide name with prefix so redaction fires
      result1 = service.process_message(
        message: "Hi, I'm new here. My name is Kenji Watanabe and I'm looking for a therapist.",
        user: user,
        context_type: "onboarding"
      )
      conversation_id = result1[:conversation_id]

      expect(result1[:message]).not_to include("[NAME_1]"),
        "Turn 1 must not contain raw [NAME_1] token"

      # Turn 2: ask something that causes the LLM to echo the name
      result2 = service.process_message(
        message: "Can you confirm what name you have for me?",
        user: user,
        conversation_id: conversation_id,
        context_type: "onboarding"
      )

      expect(result2[:message]).not_to include("[NAME_1]"),
        "Turn 2 must not contain raw [NAME_1] token — got: #{result2[:message].truncate(300)}"
      expect(result2[:message]).to include("Kenji"),
        "Turn 2 should reference the user by name — got: #{result2[:message].truncate(300)}"
    end
  end

  # ---------------------------------------------------------------------------
  # EVAL-REDACT-4: Multiple PII types — no tokens leak
  # ---------------------------------------------------------------------------
  describe "EVAL-REDACT-4: multiple PII types restored together" do
    let(:user) { create(:user, :client) }

    it "restores both name and email tokens in the response" do
      result = service.process_message(
        message: "I'm a new patient. My name is Sofia Lindgren and my email is sofia.lindgren@example.com",
        user: user,
        context_type: "onboarding"
      )

      expect(result[:message]).not_to include("[NAME_1]"),
        "Response must not contain raw [NAME_1] token"
      expect(result[:message]).not_to include("[EMAIL_1]"),
        "Response must not contain raw [EMAIL_1] token"
    end
  end

  # ---------------------------------------------------------------------------
  # EVAL-REDACT-5: No token patterns appear anywhere in any response
  # ---------------------------------------------------------------------------
  describe "EVAL-REDACT-5: no token patterns in any response" do
    let(:user) { create(:user, :client) }

    it "never outputs bracket-token patterns in onboarding responses" do
      result = service.process_message(
        message: "Hi, I'm new. My name is Amara Okafor.",
        user: user,
        context_type: "onboarding"
      )

      expect(result[:message]).not_to match(/\[(NAME|EMAIL|PHONE|SSN|DOB|POLICY|ADDRESS)_\d+\]/),
        "Response must not contain any PII token patterns — got: #{result[:message].truncate(300)}"
    end
  end
end
