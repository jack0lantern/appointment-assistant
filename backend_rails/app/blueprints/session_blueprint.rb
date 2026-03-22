class SessionBlueprint < Blueprinter::Base
  identifier :id

  fields :therapist_id, :client_id, :session_date, :session_number,
         :duration_minutes, :status, :session_type, :recording_status
end
