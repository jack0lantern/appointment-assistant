# frozen_string_literal: true

module Api
  class SafetyFlagsController < ApplicationController
    include Authenticatable

    def acknowledge
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      flag = SafetyFlag.find_by(id: params[:id])
      unless flag && flag_visible_to_therapist?(flag, therapist)
        render json: { error: "Not found" }, status: :not_found
        return
      end

      flag.update!(
        acknowledged: true,
        acknowledged_at: Time.current,
        acknowledged_by_id: current_user.id,
      )
      head :no_content
    end

    private

    def flag_visible_to_therapist?(flag, therapist)
      if flag.session_id.present?
        return Session.exists?(id: flag.session_id, therapist_id: therapist.id)
      end

      if flag.treatment_plan_version_id.present?
        tpv = TreatmentPlanVersion.find_by(id: flag.treatment_plan_version_id)
        return false unless tpv

        return tpv.treatment_plan.therapist_id == therapist.id
      end

      false
    end
  end
end
