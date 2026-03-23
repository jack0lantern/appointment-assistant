require "rails_helper"

RSpec.describe SchedulingService do
  describe ".generate_slots" do
    it "generates slots" do
      slots = described_class.generate_slots(therapist_id: 1)
      expect(slots).not_to be_empty
    end

    it "slots have required fields" do
      slots = described_class.generate_slots(therapist_id: 1)
      slots.each do |slot|
        expect(slot).to have_key(:id)
        expect(slot).to have_key(:therapist_id)
        expect(slot).to have_key(:start_time)
        expect(slot).to have_key(:end_time)
        expect(slot).to have_key(:duration_minutes)
        expect(slot).to have_key(:available)
      end
    end

    it "skips weekends" do
      # 2026-03-20 is a Friday
      friday = Time.utc(2026, 3, 20)
      slots = described_class.generate_slots(therapist_id: 1, start_date: friday, days_ahead: 4)
      slots.each do |slot|
        dt = Time.parse(slot[:start_time])
        expect(dt.wday).not_to eq(0) # Sunday
        expect(dt.wday).not_to eq(6) # Saturday
      end
    end

    it "has unique slot IDs" do
      slots = described_class.generate_slots(therapist_id: 1)
      ids = slots.map { |s| s[:id] }
      expect(ids.uniq.size).to eq(ids.size)
    end

    it "uses time-based slot IDs (therapist_id:ISO8601)" do
      slots = described_class.generate_slots(therapist_id: 42)
      slots.each do |slot|
        expect(slot[:id]).to match(/\A\d+:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(slot[:id]).to start_with("42:")
      end
    end

    it "includes correct therapist_id" do
      slots = described_class.generate_slots(therapist_id: 42)
      slots.each do |slot|
        expect(slot[:therapist_id]).to eq(42)
      end
    end

    it "duration is 60 minutes" do
      slots = described_class.generate_slots(therapist_id: 1)
      slots.each do |slot|
        expect(slot[:duration_minutes]).to eq(60)
      end
    end
  end

  describe ".get_availability" do
    it "returns slots for existing therapist" do
      therapist = create(:therapist)
      slots = described_class.get_availability(therapist_id: therapist.id)
      expect(slots).not_to be_empty
    end

    it "raises for non-existent therapist" do
      expect {
        described_class.get_availability(therapist_id: 99999)
      }.to raise_error(described_class::NotFoundError)
    end
  end

  describe ".book_appointment" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:slot_id) { described_class.get_availability(therapist_id: therapist.id).first[:id] }


    it "creates a session record" do
      result = described_class.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id
      )
      expect(result[:status]).to eq("confirmed")
      expect(result[:session_id]).to be_present
    end

    it "validates client exists" do
      expect {
        described_class.book_appointment(
          client_id: 99999,
          therapist_id: therapist.id,
          slot_id: slot_id
        )
      }.to raise_error(described_class::NotFoundError)
    end

    it "validates therapist-client relationship for delegation" do
      other_therapist = create(:therapist)
      expect {
        described_class.book_appointment(
          client_id: client.id,
          therapist_id: therapist.id,
          slot_id: slot_id,
          acting_therapist_id: other_therapist.id
        )
      }.to raise_error(described_class::AuthorizationError)
    end

    it "allows therapist to book for own client" do
      result = described_class.book_appointment(
        client_id: client.id,
        therapist_id: therapist.id,
        slot_id: slot_id,
        acting_therapist_id: therapist.id
      )
      expect(result[:status]).to eq("confirmed")
    end
  end

  describe ".cancel_appointment" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let!(:session) { create(:session, therapist: therapist, client: client, status: "scheduled") }

    it "cancels an existing session" do
      result = described_class.cancel_appointment(
        session_id: session.id,
        client_id: client.id
      )
      expect(result[:status]).to eq("cancelled")
      expect(session.reload.status).to eq("cancelled")
    end

    it "raises for non-existent session" do
      expect {
        described_class.cancel_appointment(session_id: 99999, client_id: client.id)
      }.to raise_error(described_class::NotFoundError)
    end

    it "prevents cancelling completed sessions" do
      session.update!(status: "completed")
      expect {
        described_class.cancel_appointment(session_id: session.id, client_id: client.id)
      }.to raise_error(described_class::ValidationError)
    end

    it "validates therapist authorization for delegation" do
      other_therapist = create(:therapist)
      expect {
        described_class.cancel_appointment(
          session_id: session.id,
          client_id: client.id,
          acting_therapist_id: other_therapist.id
        )
      }.to raise_error(described_class::AuthorizationError)
    end
  end
end
