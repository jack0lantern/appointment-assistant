# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Demo accounts (see README):
#   therapist@demo.health / demo123
#   therapist2@demo.health / demo123
#   client@demo.health / demo123
#   jordan.kim@demo.health, maya.patel@demo.health, etc. / demo123

unless User.exists?(email: "therapist@demo.health")
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

  tp = Therapist.create!(
    user_id: therapist.id,
    license_type: "LCSW",
    specialties: ["anxiety", "depression", "CBT"],
    preferences: {}
  )

  Client.create!(
    user_id: client_user.id,
    therapist_id: tp.id,
    name: "Alex Rivera"
  )
end

therapist_profile = Therapist.joins(:user).find_by!(users: { email: "therapist@demo.health" })

# Second therapist
therapist2 = User.find_or_create_by!(email: "therapist2@demo.health") do |u|
  u.name = "Dr. Michael Torres"
  u.role = "therapist"
  u.password = "demo123"
end

therapist_profile2 = Therapist.find_or_create_by!(user_id: therapist2.id) do |t|
  t.license_type = "LMFT"
  t.specialties = ["trauma", "family therapy", "EMDR"]
  t.preferences = {}
end

# Five additional clients
%w[Jordan Kim Maya Patel Chris Wong Taylor Nguyen Sam Foster].each_with_index do |name, i|
  email = "#{name.downcase.tr(" ", ".")}@demo.health"
  cu = User.find_or_create_by!(email: email) do |u|
    u.name = name
    u.role = "client"
    u.password = "demo123"
  end
  next if Client.exists?(user_id: cu.id)

  therapist_id = i.even? ? therapist_profile.id : therapist_profile2.id
  Client.create!(user_id: cu.id, therapist_id: therapist_id, name: name)
end
