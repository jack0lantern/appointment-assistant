require "rails_helper"

RSpec.describe Client, type: :model do
  describe "validations" do
    subject { build(:client) }

    it { should validate_uniqueness_of(:user_id).allow_nil }
    it { should validate_presence_of(:name) }
  end

  describe "associations" do
    it { should belong_to(:user).optional }
    it { should belong_to(:therapist) }
    it { should have_many(:sessions).dependent(:destroy) }
    it { should have_one(:treatment_plan).dependent(:destroy) }
    it { should have_many(:homework_items).dependent(:destroy) }
  end
end
