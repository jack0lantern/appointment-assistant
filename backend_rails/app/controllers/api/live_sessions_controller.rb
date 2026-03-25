# frozen_string_literal: true

module Api
  class LiveSessionsController < ApplicationController
    include Authenticatable

    # POST /api/clients/:client_id/sessions/live
    def create
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      client = therapist.clients.find_by(id: params[:client_id])
      unless client
        render json: { error: "Client not found" }, status: :not_found
        return
      end

      duration = (params[:duration_minutes].presence || 50).to_i
      if duration <= 0
        render json: { error: "Invalid duration" }, status: :unprocessable_entity
        return
      end

      existing_count = Session.where(client_id: client.id, therapist_id: therapist.id).count
      session = Session.create!(
        therapist_id: therapist.id,
        client_id: client.id,
        session_date: Time.current,
        session_number: existing_count + 1,
        duration_minutes: duration,
        status: "in_progress",
        session_type: "live"
      )
      session.update!(livekit_room_name: "appt-session-#{session.id}")

      render json: SessionBlueprint.render_as_hash(session), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    # POST /api/sessions/:session_id/live/token
    def token
      session = Session.find_by(id: params[:session_id])
      unless session
        render json: { error: "Session not found" }, status: :not_found
        return
      end

      unless authorized_for_live_token?(session)
        render json: { error: "Forbidden" }, status: :forbidden
        return
      end

      room = session.livekit_room_name.presence || "appt-session-#{session.id}"
      session.update!(livekit_room_name: room) if session.livekit_room_name.blank?

      identity, peer_name = live_participant_info(session)
      lk_token = LivekitTokenService.issue_token(identity: identity, room_name: room)
      render json: {
        token: lk_token,
        room_name: room,
        server_url: LivekitTokenService.server_url,
        peer_name: peer_name,
      }
    end

    # POST /api/sessions/:session_id/live/end
    def end_session
      session = Session.find_by(id: params[:session_id])
      unless session
        render json: { error: "Session not found" }, status: :not_found
        return
      end

      unless authorized_for_live_token?(session)
        render json: { error: "Forbidden" }, status: :forbidden
        return
      end

      unless session.session_type == "live"
        render json: { error: "Not a live session" }, status: :unprocessable_entity
        return
      end

      session.update!(status: "completed") if session.status == "in_progress"

      head :no_content
    end

    private

    def authorized_for_live_token?(session)
      if (t = current_user.therapist_profile) && t.id == session.therapist_id
        return true
      end
      if current_user.role == "client" && session.client.user_id == current_user.id
        return true
      end
      false
    end

    def live_participant_info(session)
      if current_user.therapist_profile&.id == session.therapist_id
        [ "therapist-#{current_user.id}", session.client.name ]
      else
        [ "client-#{current_user.id}", session.therapist.user.name ]
      end
    end
  end
end
