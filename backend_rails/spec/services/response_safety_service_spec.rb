# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResponseSafetyService do
  subject(:service) { described_class.new }

  describe "#check" do
    it "does not flag safe responses" do
      result = service.check("Here are some breathing exercises you can try.")
      expect(result[:flagged]).to be false
    end

    it "does not flag crisis resource responses" do
      result = service.check(
        "If you're thinking about ending your life, please call 988."
      )
      expect(result[:flagged]).to be false
    end

    it "flags diagnosis statements" do
      result = service.check("Based on what you've told me, you have depression.")
      expect(result[:flagged]).to be true
      expect(result[:flag_type]).to eq("inappropriate_clinical_advice")
      expect(result[:replacement]).not_to be_nil
    end

    it "flags medication advice" do
      result = service.check("You should try taking sertraline for your anxiety.")
      expect(result[:flagged]).to be true
      expect(result[:flag_type]).to eq("inappropriate_medical_advice")
    end

    it "flags dosage recommendations" do
      result = service.check("I recommend starting with 50mg daily.")
      expect(result[:flagged]).to be true
      expect(result[:flag_type]).to eq("inappropriate_medical_advice")
    end

    it "flags medical advice about stopping medication" do
      result = service.check("You should stop your medication and try therapy instead.")
      expect(result[:flagged]).to be true
      expect(result[:flag_type]).to eq("inappropriate_medical_advice")
    end

    it "flags advice to change dosage" do
      result = service.check("You should increase your dosage if you're not feeling better.")
      expect(result[:flagged]).to be true
      expect(result[:flag_type]).to eq("inappropriate_medical_advice")
    end

    it "does not flag general therapy encouragement" do
      result = service.check(
        "It sounds like talking to your therapist about this would be really helpful."
      )
      expect(result[:flagged]).to be false
    end
  end
end
