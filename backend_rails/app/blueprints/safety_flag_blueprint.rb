class SafetyFlagBlueprint < Blueprinter::Base
  identifier :id

  fields :session_id, :treatment_plan_version_id,
         :flag_type, :severity, :description, :transcript_excerpt,
         :line_start, :line_end, :source, :category,
         :acknowledged, :acknowledged_at, :acknowledged_by_id
end
