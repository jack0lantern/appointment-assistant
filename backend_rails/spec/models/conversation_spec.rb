require "rails_helper"

RSpec.describe Conversation, type: :model do
  describe "validations" do
    subject { build(:conversation) }

    it "requires a unique uuid" do
      conv1 = create(:conversation)
      conv2 = build(:conversation, uuid: conv1.uuid)
      expect(conv2).not_to be_valid
      expect(conv2.errors[:uuid]).to include("has already been taken")
    end
    it { should validate_presence_of(:context_type) }
    it { should validate_inclusion_of(:context_type).in_array(%w[general onboarding scheduling emotional_support document_upload]) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[active paused]) }
  end

  describe "associations" do
    it { should belong_to(:user) }
    it { should have_many(:messages).class_name("ConversationMessage").dependent(:destroy) }
  end

  describe "uuid generation" do
    it "auto-generates uuid on create" do
      conversation = build(:conversation, uuid: nil)
      conversation.valid?
      expect(conversation.uuid).to be_present
    end
  end

  describe "#paused?" do
    it "returns true when status is paused" do
      conversation = build(:conversation, :paused)
      expect(conversation.paused?).to be true
    end

    it "returns false when status is active" do
      conversation = build(:conversation)
      expect(conversation.paused?).to be false
    end
  end
end
