require "rails_helper"

RSpec.describe Session, type: :model do
  describe "validations" do
    it { should validate_presence_of(:session_number) }
    it { should validate_presence_of(:duration_minutes) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[scheduled in_progress completed cancelled]) }
    it { should validate_presence_of(:session_type) }
    it { should validate_inclusion_of(:session_type).in_array(%w[uploaded live]) }
  end

  describe "associations" do
    it { should belong_to(:therapist) }
    it { should belong_to(:client) }
    it { should have_one(:transcript).dependent(:destroy) }
    it { should have_one(:session_summary).dependent(:destroy) }
    it { should have_many(:safety_flags).dependent(:destroy) }
  end
end
