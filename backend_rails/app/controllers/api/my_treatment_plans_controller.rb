# frozen_string_literal: true

module Api
  class MyTreatmentPlansController < ApplicationController
    include Authenticatable

    def show
      client = current_user.client_profile
      unless client
        render json: { error: "Client profile not found" }, status: :not_found
        return
      end

      plan = client.treatment_plan
      if plan.nil? || plan.status != "approved" || plan.current_version.blank?
        head :not_found
        return
      end

      base = TreatmentPlanBlueprint.render_as_hash(plan)
      base["current_version"] = TreatmentPlanVersionBlueprint.render_as_hash(plan.current_version)
      render json: { plan: base }
    end
  end
end
