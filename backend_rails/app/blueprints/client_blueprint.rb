class ClientBlueprint < Blueprinter::Base
  identifier :id

  fields :user_id, :therapist_id, :name
end
