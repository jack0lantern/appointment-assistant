class UserBlueprint < Blueprinter::Base
  identifier :id

  fields :email, :name, :role
end
