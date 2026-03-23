class SchedulingService
  class NotFoundError < StandardError; end
  class AuthorizationError < StandardError; end
  class ValidationError < StandardError; end
  class ConflictError < StandardError; end

  @booked_slots = Set.new

  def self.booked_slots
    @booked_slots
  end

  def self.clear_booked_slots!
    @booked_slots = Set.new
  end

  DISPLAY_TIMEZONE = "America/Denver"
  SLOT_DURATION_MINUTES = 60
  # Business hours: 9 AM – 4 PM local (last slot starts at 4 PM, ends at 5 PM)
  SLOT_HOURS = (9..16).to_a.freeze

  def self.generate_slots(therapist_id:, start_date: nil, days_ahead: 7)
    start_date ||= Time.current.utc
    zone = ActiveSupport::TimeZone[DISPLAY_TIMEZONE]

    slots = []

    (1..days_ahead).each do |day_offset|
      day_in_zone = (start_date + day_offset.days).in_time_zone(zone).to_date
      next if day_in_zone.saturday? || day_in_zone.sunday?

      SLOT_HOURS.each do |hour|
        slot_local = zone.local(day_in_zone.year, day_in_zone.month, day_in_zone.day, hour, 0)
        slot_start = slot_local.utc
        slot_end = slot_start + SLOT_DURATION_MINUTES.minutes

        slots << {
          id: "#{therapist_id}:#{slot_start.iso8601}",
          therapist_id: therapist_id,
          start_time: slot_start.iso8601,
          end_time: slot_end.iso8601,
          duration_minutes: SLOT_DURATION_MINUTES,
          available: true
        }
      end
    end

    slots
  end

  def self.get_availability(therapist_id:, start_date: nil, include_booked: false)
    therapist = Therapist.find_by(id: therapist_id)
    raise NotFoundError, "Therapist #{therapist_id} not found" unless therapist

    slots = generate_slots(therapist_id: therapist_id, start_date: start_date)
    return slots if include_booked
    slots.reject { |s| @booked_slots.include?(s[:id]) }
  end

  def self.book_appointment(client_id:, therapist_id:, slot_id:, session_date: nil, acting_therapist_id: nil)
    client = Client.find_by(id: client_id)
    raise NotFoundError, "Client #{client_id} not found" unless client

    if acting_therapist_id.present?
      unless client.therapist_id == acting_therapist_id
        raise AuthorizationError,
              "Therapist #{acting_therapist_id} is not authorized to book for client #{client_id}"
      end
    end

    therapist = Therapist.find_by(id: therapist_id)
    raise NotFoundError, "Therapist #{therapist_id} not found" unless therapist

    raise ConflictError, "Slot already booked" if @booked_slots.include?(slot_id)

    session_date ||= 1.day.from_now

    existing_count = Session.where(client_id: client_id, therapist_id: therapist_id).count

    new_session = Session.create!(
      therapist_id: therapist_id,
      client_id: client_id,
      session_date: session_date,
      session_number: existing_count + 1,
      duration_minutes: SLOT_DURATION_MINUTES,
      status: "scheduled",
      session_type: "live"
    )

    @booked_slots.add(slot_id)
    Rails.logger.info("Appointment booked: session=#{new_session.id} client=#{client_id} therapist=#{therapist_id}")

    {
      session_id: new_session.id,
      status: "confirmed",
      slot_id: slot_id,
      session_date: session_date.iso8601,
      duration_minutes: SLOT_DURATION_MINUTES
    }
  end

  def self.cancel_appointment(session_id:, client_id:, acting_therapist_id: nil)
    session = Session.find_by(id: session_id, client_id: client_id)
    raise NotFoundError, "Session not found or access denied" unless session

    if acting_therapist_id.present? && session.therapist_id != acting_therapist_id
      raise AuthorizationError,
            "Therapist #{acting_therapist_id} is not authorized to cancel this session"
    end

    raise ValidationError, "Cannot cancel a completed session" if session.status == "completed"

    session.update!(status: "cancelled")

    # Re-open the slot so it appears available again
    if session.session_date.present?
      freed_slot_id = "#{session.therapist_id}:#{session.session_date.utc.iso8601}"
      @booked_slots.delete(freed_slot_id)
    end

    Rails.logger.info("Appointment cancelled: session=#{session_id} client=#{client_id}")

    { session_id: session_id, status: "cancelled" }
  end
end
