# frozen_string_literal: true

module Api
  class ClientSessionsController < ApplicationController
    include Authenticatable

    # GET /api/my/sessions — session history for current client
    def index
      client = current_user.client_profile
      unless client
        render json: { error: "Client profile not found" }, status: :not_found
        return
      end

      sessions = Session
        .where(client_id: client.id, status: "completed")
        .includes(:session_summary)
        .order(session_date: :desc, id: :desc)

      data = sessions.map do |s|
        hash = SessionBlueprint.render_as_hash(s)
        hash["session_date"] = s.session_date&.iso8601
        if s.session_summary
          hash["summary"] = {
            therapist_summary: s.session_summary.therapist_summary,
            client_summary: s.session_summary.client_summary,
            key_themes: s.session_summary.key_themes || []
          }
        else
          hash["summary"] = nil
        end
        hash
      end

      render json: data
    end
  end
end
