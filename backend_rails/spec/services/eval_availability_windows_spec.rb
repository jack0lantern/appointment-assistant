# frozen_string_literal: true

require "rails_helper"

# Evaluation: get_available_slots groups slots into time windows per day,
# collapsing consecutive hours into ranges (e.g. "9:00 AM – 2:00 PM")
# so the agent can present compact availability instead of listing every slot.
RSpec.describe "Availability windows evaluation", type: :service do
  let!(:therapist) { create(:therapist) }
  let(:user) { create(:user, :client) }
  let!(:client_record) { create(:client, user: user, therapist: therapist) }

  let(:zone) { ActiveSupport::TimeZone[SchedulingService::DISPLAY_TIMEZONE] }

  def auth_for(user, client)
    AgentTools::ToolAuthContext.new(
      user_id: user.id,
      role: "client",
      client_id: client.id,
      therapist_id: therapist.id
    )
  end

  def slot_at_local_hour(hour)
    SchedulingService.get_availability(therapist_id: therapist.id, include_booked: true).find do |s|
      Time.parse(s[:start_time]).in_time_zone(zone).hour == hour
    end
  end

  before do
    user.reload

  end

  # ---------------------------------------------------------------------------
  # No bookings: one continuous window per day
  # ---------------------------------------------------------------------------
  describe "no bookings — full day window" do
    it "returns one window per day covering 9 AM – 5 PM" do
      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      expect(result[:days]).to be_an(Array)
      expect(result[:days]).not_to be_empty

      first_day = result[:days].first
      expect(first_day[:date]).to be_a(String)
      expect(first_day[:windows]).to eq(["9:00 AM – 5:00 PM"])
      expect(first_day[:slots]).to be_an(Array)
      expect(first_day[:slots].length).to eq(8) # 9,10,11,12,1,2,3,4
    end
  end

  # ---------------------------------------------------------------------------
  # Middle slot booked: splits into two windows
  # ---------------------------------------------------------------------------
  describe "middle slot booked — split windows" do
    it "splits into two windows when 2 PM is booked" do
      slot_2pm = slot_at_local_hour(14)
      SchedulingService.book_appointment(
        client_id: client_record.id,
        therapist_id: therapist.id,
        slot_id: slot_2pm[:id],
        session_date: Time.parse(slot_2pm[:start_time])
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      booked_date = Time.parse(slot_2pm[:start_time]).in_time_zone(zone)
      booked_day = result[:days].find { |d| d[:date] == booked_date.strftime("%A, %B %d") }

      expect(booked_day).to be_present
      expect(booked_day[:windows]).to eq(["9:00 AM – 2:00 PM", "3:00 PM – 5:00 PM"])
      expect(booked_day[:slots].length).to eq(7) # 8 - 1
    end

    it "splits into two windows when 12 PM is booked" do
      slot_noon = slot_at_local_hour(12)
      SchedulingService.book_appointment(
        client_id: client_record.id,
        therapist_id: therapist.id,
        slot_id: slot_noon[:id],
        session_date: Time.parse(slot_noon[:start_time])
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      booked_date = Time.parse(slot_noon[:start_time]).in_time_zone(zone)
      booked_day = result[:days].find { |d| d[:date] == booked_date.strftime("%A, %B %d") }

      expect(booked_day[:windows]).to eq(["9:00 AM – 12:00 PM", "1:00 PM – 5:00 PM"])
    end
  end

  # ---------------------------------------------------------------------------
  # First slot booked: window starts later
  # ---------------------------------------------------------------------------
  describe "first slot booked — window starts later" do
    it "starts at 10 AM when 9 AM is booked" do
      slot_9am = slot_at_local_hour(9)
      SchedulingService.book_appointment(
        client_id: client_record.id,
        therapist_id: therapist.id,
        slot_id: slot_9am[:id],
        session_date: Time.parse(slot_9am[:start_time])
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      booked_date = Time.parse(slot_9am[:start_time]).in_time_zone(zone)
      booked_day = result[:days].find { |d| d[:date] == booked_date.strftime("%A, %B %d") }

      expect(booked_day[:windows]).to eq(["10:00 AM – 5:00 PM"])
    end
  end

  # ---------------------------------------------------------------------------
  # Last slot booked: window ends earlier
  # ---------------------------------------------------------------------------
  describe "last slot booked — window ends earlier" do
    it "ends at 4 PM when 4 PM is booked" do
      slot_4pm = slot_at_local_hour(16)
      SchedulingService.book_appointment(
        client_id: client_record.id,
        therapist_id: therapist.id,
        slot_id: slot_4pm[:id],
        session_date: Time.parse(slot_4pm[:start_time])
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      booked_date = Time.parse(slot_4pm[:start_time]).in_time_zone(zone)
      booked_day = result[:days].find { |d| d[:date] == booked_date.strftime("%A, %B %d") }

      expect(booked_day[:windows]).to eq(["9:00 AM – 4:00 PM"])
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple consecutive slots booked: larger gap
  # ---------------------------------------------------------------------------
  describe "consecutive slots booked — larger gap" do
    it "creates a gap when 11 AM and 12 PM are both booked" do
      [11, 12].each do |hour|
        slot = slot_at_local_hour(hour)
        SchedulingService.book_appointment(
          client_id: client_record.id,
          therapist_id: therapist.id,
          slot_id: slot[:id],
          session_date: Time.parse(slot[:start_time])
        )
      end

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      # Find the affected day (first day with slots, which has 11 and 12)
      first_slot = slot_at_local_hour(11)
      booked_date = Time.parse(first_slot[:start_time]).in_time_zone(zone)
      booked_day = result[:days].find { |d| d[:date] == booked_date.strftime("%A, %B %d") }

      expect(booked_day[:windows]).to eq(["9:00 AM – 11:00 AM", "1:00 PM – 5:00 PM"])
      expect(booked_day[:slots].length).to eq(6) # 8 - 2
    end
  end

  # ---------------------------------------------------------------------------
  # All slots booked on a day: day excluded entirely
  # ---------------------------------------------------------------------------
  describe "all slots booked — day excluded" do
    it "omits the day from results when every slot is booked" do
      first_slot = slot_at_local_hour(9)
      booked_date = Time.parse(first_slot[:start_time]).in_time_zone(zone)
      date_str = booked_date.strftime("%A, %B %d")

      SchedulingService::SLOT_HOURS.each do |hour|
        slot = SchedulingService.get_availability(therapist_id: therapist.id, include_booked: true).find do |s|
          local = Time.parse(s[:start_time]).in_time_zone(zone)
          local.hour == hour && local.to_date == booked_date.to_date
        end
        next unless slot
        SchedulingService.book_appointment(
          client_id: client_record.id,
          therapist_id: therapist.id,
          slot_id: slot[:id],
          session_date: Time.parse(slot[:start_time])
        )
      end

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      day_dates = result[:days].map { |d| d[:date] }
      expect(day_dates).not_to include(date_str)
    end
  end

  # ---------------------------------------------------------------------------
  # Individual slots still present for booking
  # ---------------------------------------------------------------------------
  describe "individual slots preserved for booking" do
    it "each slot has slot_id and time for the agent to book" do
      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { therapist_id: therapist.id },
        auth_context: auth_for(user, client_record)
      )

      first_day = result[:days].first
      first_day[:slots].each do |slot|
        expect(slot[:slot_id]).to be_a(String)
        expect(slot[:time]).to match(/\d{1,2}:\d{2} [AP]M/)
      end
    end
  end
end
