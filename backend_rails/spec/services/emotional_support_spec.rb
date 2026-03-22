require "rails_helper"

RSpec.describe EmotionalSupportService do
  describe ".grounding_exercise" do
    it "returns a non-empty string" do
      result = described_class.grounding_exercise
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "contains supportive/actionable content" do
      10.times do
        result = described_class.grounding_exercise
        expect(result.downcase).to match(/breathe|feet|see|touch|hear|ground/)
      end
    end
  end

  describe ".validation_message" do
    it "returns a non-empty string" do
      result = described_class.validation_message
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "uses validating tone" do
      10.times do
        result = described_class.validation_message
        expect(result.downcase).not_to include("you should")
      end
    end
  end

  describe ".psychoeducation" do
    it "returns content for known topic" do
      result = described_class.psychoeducation("anxiety")
      expect(result).not_to be_nil
      expect(result).not_to be_empty
    end

    it "returns nil for unknown topic" do
      result = described_class.psychoeducation("nonexistent_topic")
      expect(result).to be_nil
    end

    it "returns first_session content mentioning session" do
      result = described_class.psychoeducation("first_session")
      expect(result).not_to be_nil
      expect(result.downcase).to include("session")
    end
  end

  describe ".what_to_expect" do
    it "returns onboarding content" do
      result = described_class.what_to_expect("onboarding")
      expect(result).not_to be_nil
      expect(result.downcase).to match(/onboarding|information/)
    end

    it "returns first_appointment content" do
      result = described_class.what_to_expect("first_appointment")
      expect(result).not_to be_nil
      expect(result).to match(/50 minutes|appointment/i)
    end

    it "returns nil for unknown context" do
      result = described_class.what_to_expect("unknown_context")
      expect(result).to be_nil
    end
  end
end
