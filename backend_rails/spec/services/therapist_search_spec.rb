# frozen_string_literal: true

require "rails_helper"

RSpec.describe TherapistSearchService do
  subject(:service) { described_class.new }

  let!(:anxiety_therapist) do
    create(:therapist, specialties: ["anxiety", "ptsd"],
           user: create(:user, :therapist, name: "Jane Smith"))
  end

  let!(:depression_therapist) do
    create(:therapist, specialties: ["depression", "grief"],
           user: create(:user, :therapist, name: "John Doe"))
  end

  let!(:cbt_therapist) do
    create(:therapist, specialties: ["cbt", "anxiety"],
           user: create(:user, :therapist, name: "Alice Johnson"))
  end

  describe "#search" do
    it "searches by specialty" do
      results = service.search(specialty: "anxiety")

      names = results.map(&:name)
      expect(names).to include("Jane Smith", "Alice Johnson")
      expect(names).not_to include("John Doe")
    end

    it "fuzzy-matches by name" do
      results = service.search(query: "smith")

      expect(results.length).to eq(1)
      expect(results.first.name).to eq("Jane Smith")
    end

    it "returns therapist names as display labels, not UUIDs" do
      results = service.search

      results.each do |r|
        expect(r.display_label).to eq(r.name)
        expect(r.to_h).not_to have_key(:id)
        expect(r.to_h).not_to have_key(:therapist_id)
      end
    end

    it "disambiguates duplicate names with license type" do
      create(:therapist, license_type: "LMFT", specialties: ["trauma"],
             user: create(:user, :therapist, name: "Jane Smith"))
      # Now we have two Jane Smiths (anxiety_therapist is LCSW, new one is LMFT)
      results = service.search(query: "jane smith")

      labels = results.map(&:display_label)
      expect(labels).to contain_exactly("Jane Smith", a_string_matching(/\AJane Smith \([A-Za-z]+\)\z/))
    end

    it "returns empty results for no match" do
      results = service.search(query: "nonexistent")

      expect(results).to be_empty
    end

    it "returns all therapists when no filters given" do
      results = service.search

      expect(results.length).to be >= 3
      expect(results.map(&:name)).to include("Jane Smith", "John Doe", "Alice Johnson")
    end
  end

  describe "#resolve_label" do
    it "maps display label back to therapist id after search" do
      results = service.search(query: "smith")
      label = results.first.display_label

      expect(service.resolve_label(label)).to eq(anxiety_therapist.id)
    end

    it "returns nil for unknown label" do
      expect(service.resolve_label("Dr. Z")).to be_nil
    end
  end

  describe "#confirm_selection" do
    let(:client_user) { create(:user, :client) }
    let(:conversation) do
      create(:conversation, :onboarding, user: client_user, onboarding_progress: {})
    end

    it "saves selected_therapist_id on confirmation" do
      results = service.search(query: "smith")
      label = results.first.display_label

      therapist_id = service.confirm_selection(
        conversation: conversation,
        display_label: label
      )

      expect(therapist_id).to eq(anxiety_therapist.id)
      conversation.reload
      expect(conversation.onboarding_progress["selected_therapist_id"]).to eq(anxiety_therapist.id)
    end

    it "returns nil for unknown label" do
      result = service.confirm_selection(
        conversation: conversation,
        display_label: "Dr. ZZZ"
      )

      expect(result).to be_nil
    end
  end
end
