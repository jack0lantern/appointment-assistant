class SchedulingService
  class NotFoundError < StandardError; end
  class AuthorizationError < StandardError; end
  class ValidationError < StandardError; end
  class ConflictError < StandardError; end

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

    booked_times = booked_times_for(therapist_id, slots)
    slots.reject { |s| booked_times.include?(Time.parse(s[:start_time]).utc.to_i) }
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

    # Resolve session_date from slot_id (format: therapist_id:ISO8601) when not provided
    if session_date.nil? && slot_id.is_a?(String) && slot_id.include?(":")
      _prefix, datetime_str = slot_id.split(":", 2)
      session_date = Time.parse(datetime_str) rescue nil
    end
    session_date ||= 1.day.from_now

    # Check DB for existing scheduled session at this time for this therapist
    conflict = Session.where(therapist_id: therapist_id, status: "scheduled")
      .where("session_date BETWEEN ? AND ?", session_date - 30.seconds, session_date + 30.seconds)
      .exists?
    raise ConflictError, "Slot already booked" if conflict

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
    Rails.logger.info("Appointment cancelled: session=#{session_id} client=#{client_id}")

    { session_id: session_id, status: "cancelled" }
  end

  # Query the DB for scheduled sessions that overlap with the given slots' time range
  def self.booked_times_for(therapist_id, slots)
    return Set.new if slots.empty?

    start_times = slots.map { |s| Time.parse(s[:start_time]) }
    range_start = start_times.min
    range_end = start_times.max + SLOT_DURATION_MINUTES.minutes

    Session.where(therapist_id: therapist_id, status: "scheduled")
      .where("session_date >= ? AND session_date <= ?", range_start, range_end)
      .pluck(:session_date)
      .map { |t| t.utc.to_i }
      .to_set
  end
  private_class_method :booked_times_for
end
