# frozen_string_literal: true

module Api
  class TherapistAppointmentsController < ApplicationController
    include Authenticatable

    # GET /api/therapist/appointments — only upcoming scheduled sessions for current therapist
    def index
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      sessions = Session
        .where(therapist_id: therapist.id, status: "scheduled")
        .where("session_date >= ?", Time.current)
        .includes(:client)
        .order(:session_date)

      appointments = sessions.map do |s|
        {
          session_id: s.id,
          session_date: s.session_date.iso8601,
          client_id: s.client_id,
          client_name: s.client.name,
          duration_minutes: s.duration_minutes
        }
      end

      render json: { appointments: appointments }
    end
  end
end
