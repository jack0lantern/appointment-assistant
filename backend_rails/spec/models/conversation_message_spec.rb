require "rails_helper"

RSpec.describe ConversationMessage, type: :model do
  describe "validations" do
    it { should validate_presence_of(:role) }
    it { should validate_inclusion_of(:role).in_array(%w[user assistant system tool]) }
    it { should validate_presence_of(:content) }
  end

  describe "associations" do
    it { should belong_to(:conversation) }
  end
end
