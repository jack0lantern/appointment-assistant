class TherapistBlueprint < Blueprinter::Base
  identifier :id

  fields :user_id, :license_type, :specialties, :preferences, :slug
end

