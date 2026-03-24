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

    # GET /api/clients/:id
    def show
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      client = therapist.clients.find_by(id: params[:id])
      unless client
        render json: { error: "Client not found" }, status: :not_found
        return
      end

      sessions = client.sessions.where(status: "completed").order(session_date: :desc, id: :desc).limit(10)
      plan = client.treatment_plan
      # #region agent log
      begin
        File.open("/Users/jackjiang/GitHub/partner-projects/appointment-assistant/.cursor/debug-3b6b0a.log", "a") do |f|
          f.puts({
            sessionId: "3b6b0a",
            hypothesisId: "H1",
            location: "Api::ClientsController#show",
            message: "treatment plan record state",
            data: { param_id: params[:id].to_s, plan_present: plan.present?, plan_id: plan&.id },
            timestamp: (Time.now.to_f * 1000).to_i,
          }.to_json)
        end
      rescue StandardError
      end
      # #endregion
      session_ids = client.sessions.pluck(:id)
      version_ids = TreatmentPlanVersion.joins(:treatment_plan).where(treatment_plans: { client_id: client.id }).pluck(:id)
      safety_flags = SafetyFlag
        .where(session_id: session_ids)
        .or(SafetyFlag.where(treatment_plan_version_id: version_ids))

      treatment_plan_hash = if plan
        begin
          base = TreatmentPlanBlueprint.render_as_hash(plan)
          base["current_version"] = plan.current_version ? TreatmentPlanVersionBlueprint.render_as_hash(plan.current_version) : nil
          base["versions"] = plan.versions.map { |v| TreatmentPlanVersionBlueprint.render_as_hash(v) }
          base
        rescue StandardError => e
          # #region agent log
          begin
            File.open("/Users/jackjiang/GitHub/partner-projects/appointment-assistant/.cursor/debug-3b6b0a.log", "a") do |f|
              f.puts({
                sessionId: "3b6b0a",
                hypothesisId: "H4",
                location: "Api::ClientsController#show",
                message: "treatment_plan serialization error",
                data: { error_class: e.class.name },
                timestamp: (Time.now.to_f * 1000).to_i,
              }.to_json)
            end
          rescue StandardError
          end
          # #endregion
          raise
        end
      end

      render json: {
        client: ClientBlueprint.render_as_hash(client),
        sessions: SessionBlueprint.render_as_hash(sessions),
        treatment_plan: treatment_plan_hash,
        safety_flags: SafetyFlagBlueprint.render_as_hash(safety_flags),
      }
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
