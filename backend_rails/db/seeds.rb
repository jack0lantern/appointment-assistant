# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Demo accounts (see README):
#   therapist@demo.health / demo123
#   client@demo.health / demo123

return if User.exists?(email: "therapist@demo.health")

therapist = User.create!(
  email: "therapist@demo.health",
  name: "Dr. Sarah Chen",
  role: "therapist",
  password: "demo123"
)

client_user = User.create!(
  email: "client@demo.health",
  name: "Alex Rivera",
  role: "client",
  password: "demo123"
)

therapist_profile = Therapist.create!(
  user_id: therapist.id,
  license_type: "LCSW",
  specialties: ["anxiety", "depression", "CBT"],
  preferences: {}
)

Client.create!(
  user_id: client_user.id,
  therapist_id: therapist_profile.id,
  name: "Alex Rivera"
)
