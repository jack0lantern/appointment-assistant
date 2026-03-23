# frozen_string_literal: true

module Api
  class ClientsController < ApplicationController
    include Authenticatable

    # GET /api/clients
    def index
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      clients = therapist.clients
      render json: ClientBlueprint.render_as_hash(clients)
    end

    # POST /api/clients
    def create
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      client = therapist.clients.build(name: params[:name])
      if client.save
        render json: ClientBlueprint.render_as_hash(client), status: :created
      else
        render json: { error: client.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end
  end
end
