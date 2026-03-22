# frozen_string_literal: true

require "rails_helper"

RSpec.describe InputSafetyService do
  subject(:service) { described_class.new }

  describe "#check" do
    it "detects crisis language (suicidal ideation)" do
      result = service.check("I want to kill myself")
      expect(result[:flagged]).to be true
      expect(result[:escalated]).to be true
      expect(result[:flag_type]).to eq("crisis")
    end

    it "detects crisis language (self-harm)" do
      result = service.check("I've been cutting myself")
      expect(result[:flagged]).to be true
      expect(result[:escalated]).to be true
    end

    it "detects crisis language (harm to others)" do
      result = service.check("I want to hurt someone")
      expect(result[:flagged]).to be true
      expect(result[:escalated]).to be true
    end

    it "does not flag normal messages" do
      result = service.check("I'd like to book an appointment for next week")
      expect(result[:flagged]).to be false
      expect(result[:escalated]).to be false
    end

    it "does not flag emotional but non-crisis messages" do
      result = service.check("I'm feeling really overwhelmed and anxious right now")
      expect(result[:flagged]).to be false
    end
  end
end
