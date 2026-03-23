# frozen_string_literal: true

module Api
  class ClientAppointmentsController < ApplicationController
    include Authenticatable

    # GET /api/my/appointments — only upcoming scheduled sessions for current client
    def index
      client = current_user.client_profile
      unless client
        render json: { error: "Client profile not found" }, status: :not_found
        return
      end

      sessions = Session
        .where(client_id: client.id, status: "scheduled")
        .where("session_date >= ?", Time.current)
        .includes(therapist: :user)
        .order(:session_date)

      appointments = sessions.map do |s|
        {
          session_id: s.id,
          session_date: s.session_date.iso8601,
          therapist_name: s.therapist&.user&.name || "Your therapist",
          duration_minutes: s.duration_minutes
        }
      end

      render json: { appointments: appointments }
    end
  end
end
