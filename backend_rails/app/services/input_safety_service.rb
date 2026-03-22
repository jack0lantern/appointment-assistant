# frozen_string_literal: true

# Checks user input for crisis language patterns.
# Port of check_input_safety from Python agent_service.py.
class InputSafetyService
  CRISIS_PATTERNS = [
    /\b(want\s+to\s+(die|end\s+(it|my\s+life|everything))|kill\s+myself|suicid(e|al)|don'?t\s+want\s+to\s+(be\s+alive|live|exist)|better\s+off\s+dead|end(ing)?\s+my\s+life|take\s+my\s+(own\s+)?life)/i,
    /\b(cut(ting)?\s+myself|hurt(ing)?\s+myself|burn(ing)?\s+myself|hit(ting)?\s+myself)/i,
    /\b(kill\s+(him|her|them|someone)|want\s+to\s+hurt\s+(him|her|them|someone))/i
  ].freeze

  # Returns a hash with :flagged, :flag_type, :escalated
  def check(message)
    CRISIS_PATTERNS.each do |pattern|
      if pattern.match?(message)
        return { flagged: true, flag_type: "crisis", escalated: true }
      end
    end
    { flagged: false, flag_type: nil, escalated: false }
  end
end
