require "rails_helper"

RSpec.describe Therapist, type: :model do
  describe "validations" do
    subject { build(:therapist) }

    it { should validate_uniqueness_of(:user_id) }
    it { should validate_presence_of(:license_type) }
  end

  describe "associations" do
    it { should belong_to(:user) }
    it { should have_many(:clients).dependent(:destroy) }
    it { should have_many(:sessions).dependent(:destroy) }
    it { should have_many(:treatment_plans).dependent(:destroy) }
  end
end
