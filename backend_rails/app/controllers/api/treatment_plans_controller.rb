# frozen_string_literal: true

module Api
  class TreatmentPlansController < ApplicationController
    include Authenticatable

    def draft
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return
      end

      plans = TreatmentPlan.where(therapist_id: therapist.id, status: "draft").includes(:client).order(updated_at: :desc)
      render json: plans.map { |p|
        {
          plan_id: p.id,
          client_id: p.client_id,
          client_name: p.client.name,
          created_at: p.created_at.iso8601(3),
        }
      }
    end

    def approve
      plan = find_owned_plan
      return unless plan

      if plan.status == "approved"
        head :ok
        return
      end

      unless plan.current_version
        render json: { error: "No plan version to approve" }, status: :unprocessable_entity
        return
      end

      if unacknowledged_safety_flags?(plan.client)
        render json: { error: "Acknowledge all safety flags before approving" }, status: :unprocessable_entity
        return
      end

      plan.update!(status: "approved")
      head :ok
    end

    def edit
      plan = find_owned_plan
      return unless plan

      content = params[:therapist_content]
      unless content.is_a?(ActionController::Parameters) || content.is_a?(Hash)
        render json: { error: "therapist_content required" }, status: :unprocessable_entity
        return
      end

      content = content.to_unsafe_h if content.is_a?(ActionController::Parameters)
      summary = params[:change_summary].presence || "Therapist edit"

      TreatmentPlan.transaction do
        next_num = (plan.versions.maximum(:version_number) || 0) + 1
        prev = plan.current_version
        client_copy = prev&.client_content || {}

        version = plan.versions.create!(
          version_number: next_num,
          therapist_content: content,
          client_content: client_copy,
          change_summary: summary,
          source: "therapist_edit",
          session_id: prev&.session_id,
        )
        plan.update!(current_version_id: version.id, status: "draft")
      end

      head :ok
    end

    def versions
      plan = find_owned_plan
      return unless plan

      rows = plan.versions.order(version_number: :desc).map do |v|
        {
          id: v.id,
          version_number: v.version_number,
          source: v.source,
          session_id: v.session_id,
          change_summary: v.change_summary,
          created_at: v.created_at&.iso8601(3),
        }
      end
      render json: rows
    end

    def diff
      plan = find_owned_plan
      return unless plan

      v1 = plan.versions.find_by(version_number: params[:v1].to_i)
      v2 = plan.versions.find_by(version_number: params[:v2].to_i)
      unless v1 && v2
        render json: { error: "Versions not found" }, status: :not_found
        return
      end

      render json: { diffs: therapist_content_diffs(v1.therapist_content, v2.therapist_content) }
    end

    private

    def find_owned_plan
      therapist = current_user.therapist_profile
      unless therapist
        render json: { error: "Therapist profile not found" }, status: :not_found
        return nil
      end

      plan = TreatmentPlan.find_by(id: params[:id])
      unless plan && plan.therapist_id == therapist.id
        render json: { error: "Not found" }, status: :not_found
        return nil
      end

      plan
    end

    def unacknowledged_safety_flags?(client)
      session_ids = client.sessions.pluck(:id)
      version_ids = TreatmentPlanVersion.joins(:treatment_plan).where(treatment_plans: { client_id: client.id }).pluck(:id)
      SafetyFlag
        .where(session_id: session_ids)
        .or(SafetyFlag.where(treatment_plan_version_id: version_ids))
        .where(acknowledged: false)
        .exists?
    end

    def therapist_content_diffs(old_content, new_content)
      old_h = (old_content || {}).stringify_keys
      new_h = (new_content || {}).stringify_keys
      keys = (old_h.keys | new_h.keys).sort

      keys.each_with_object({}) do |key, out|
        old_t = section_text_for_diff(old_h[key])
        new_t = section_text_for_diff(new_h[key])
        next if old_t == new_t

        out[key] = {
          "status" => "modified",
          "old_text" => old_t,
          "new_text" => new_t,
        }
      end
    end

    def section_text_for_diff(value)
      case value
      when Array
        value.map { |x| x.is_a?(Hash) ? JSON.pretty_generate(x) : x.to_s }.join("\n")
      when Hash
        JSON.pretty_generate(value)
      when nil
        ""
      else
        value.to_s
      end
    end
  end
end
