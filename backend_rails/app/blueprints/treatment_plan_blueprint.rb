class TreatmentPlanBlueprint < Blueprinter::Base
  identifier :id

  fields :client_id, :therapist_id, :current_version_id, :status
end
