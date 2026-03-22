# frozen_string_literal: true

module Api
  class AgentSchedulingController < ApplicationController
    include Authenticatable

    # GET /api/agent/scheduling/availability?therapist_id=N
    def availability
      therapist_id = params[:therapist_id]
      unless therapist_id.present?
        render json: { error: "therapist_id is required" }, status: :unprocessable_entity
        return
      end

      slots = SchedulingService.get_availability(therapist_id: therapist_id.to_i)
      render json: { slots: slots }
    rescue SchedulingService::NotFoundError => e
      render json: { error: e.message }, status: :not_found
    end

    # POST /api/agent/scheduling/book
    def book
      therapist_id = params[:therapist_id]
      slot_id = params[:slot_id]

      unless therapist_id.present? && slot_id.present?
        render json: { error: "therapist_id and slot_id are required" }, status: :unprocessable_entity
        return
      end

      client_id, acting_therapist_id = resolve_client_and_therapist("booking")
      return if performed? # rendered an error

      session_date = params[:session_date] ? Time.parse(params[:session_date]) : nil

      result = SchedulingService.book_appointment(
        client_id: client_id,
        therapist_id: therapist_id.to_i,
        slot_id: slot_id,
        session_date: session_date,
        acting_therapist_id: acting_therapist_id
      )

      render json: result
    rescue SchedulingService::NotFoundError, SchedulingService::ValidationError => e
      render json: { error: e.message }, status: :bad_request
    rescue SchedulingService::AuthorizationError => e
      render json: { error: e.message }, status: :forbidden
    end

    # POST /api/agent/scheduling/cancel
    def cancel
      session_id = params[:session_id]

      unless session_id.present?
        render json: { error: "session_id is required" }, status: :unprocessable_entity
        return
      end

      client_id, acting_therapist_id = resolve_client_and_therapist("cancelling")
      return if performed?

      result = SchedulingService.cancel_appointment(
        session_id: session_id.to_i,
        client_id: client_id,
        acting_therapist_id: acting_therapist_id
      )

      render json: result
    rescue SchedulingService::NotFoundError => e
      render json: { error: e.message }, status: :not_found
    rescue SchedulingService::AuthorizationError => e
      render json: { error: e.message }, status: :forbidden
    rescue SchedulingService::ValidationError => e
      render json: { error: e.message }, status: :bad_request
    end

    private

    # Returns [client_id, acting_therapist_id] or renders an error and returns nil.
    def resolve_client_and_therapist(action)
      if current_user.client_profile
        [current_user.client_profile.id, nil]
      elsif current_user.therapist_profile
        client_id = params[:client_id]
        unless client_id.present?
          render json: { error: "Therapist must provide client_id when #{action} on behalf of a client" }, status: :bad_request
          return [nil, nil]
        end
        [client_id.to_i, current_user.therapist_profile.id]
      else
        render json: { error: "No client or therapist profile found" }, status: :forbidden
        [nil, nil]
      end
    end
  end
end
