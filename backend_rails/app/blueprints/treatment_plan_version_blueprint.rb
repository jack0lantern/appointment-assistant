class TreatmentPlanVersionBlueprint < Blueprinter::Base
  identifier :id

  fields :treatment_plan_id, :version_number, :session_id,
         :therapist_content, :client_content, :change_summary,
         :source, :ai_metadata, :created_at
end
