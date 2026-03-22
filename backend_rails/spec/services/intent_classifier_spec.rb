require "rails_helper"

RSpec.describe IntentClassifier do
  describe ".classify" do
    it "classifies scheduling keywords as scheduling" do
      [
        "I need to book an appointment for next Tuesday",
        "Can I reschedule my session?",
        "What times are available tomorrow?",
        "I want to cancel my appointment",
        "Is there a slot this week?"
      ].each do |msg|
        expect(described_class.classify(msg)).to eq("scheduling"), "Expected '#{msg}' to be scheduling"
      end
    end

    it "classifies onboarding keywords as onboarding" do
      [
        "I'm a new patient and need to register",
        "I want to sign up for therapy",
        "I need to do my intake paperwork",
        "How do I start the intake process?",
        "I'm new here and getting started"
      ].each do |msg|
        expect(described_class.classify(msg)).to eq("onboarding"), "Expected '#{msg}' to be onboarding"
      end
    end

    it "classifies emotional support keywords as emotional_support" do
      [
        "I'm feeling really overwhelmed and anxious right now",
        "I'm so stressed and scared",
        "I feel depressed and hopeless",
        "I can't cope anymore",
        "I'm feeling terrible today"
      ].each do |msg|
        expect(described_class.classify(msg)).to eq("emotional_support"), "Expected '#{msg}' to be emotional_support"
      end
    end

    it "classifies document upload keywords as document_upload" do
      [
        "I want to upload my insurance card",
        "How do I scan my ID card?",
        "I need to submit a document",
        "Can I upload a photo of my form?"
      ].each do |msg|
        expect(described_class.classify(msg)).to eq("document_upload"), "Expected '#{msg}' to be document_upload"
      end
    end

    it "classifies unknown messages as general" do
      [
        "What services do you offer?",
        "Hello there",
        "Tell me about your platform"
      ].each do |msg|
        expect(described_class.classify(msg)).to eq("general"), "Expected '#{msg}' to be general"
      end
    end

    it "prioritizes document_upload over scheduling when both match" do
      # "upload" matches document, "appointment" matches scheduling — document wins
      result = described_class.classify("I want to upload a form for my appointment")
      expect(result).to eq("document_upload")
    end
  end
end
