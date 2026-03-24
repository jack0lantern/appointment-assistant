require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:role) }
    it { should validate_inclusion_of(:role).in_array(%w[client therapist admin]) }
  end

  describe "associations" do
    it { should have_one(:therapist_profile).class_name("Therapist").dependent(:destroy) }
    it { should have_one(:client_profile).class_name("Client").dependent(:destroy) }
    it { should have_many(:conversations).dependent(:destroy) }
  end

  describe "password storage" do
    it "uses password_digest column for has_secure_password (not legacy password_hash)" do
      expect(User.column_names).to include("password_digest")
      expect(User.column_names).not_to include("password_hash")
    end
  end

  describe "secure password" do
    it "authenticates with correct password" do
      user = create(:user, password: "secret123")
      expect(user.authenticate("secret123")).to eq(user)
    end

    it "rejects incorrect password" do
      user = create(:user, password: "secret123")
      expect(user.authenticate("wrong")).to be_falsey
    end
  end
end
