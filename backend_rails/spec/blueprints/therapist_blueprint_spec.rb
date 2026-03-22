require "rails_helper"

RSpec.describe "TherapistBlueprint" do
  it "serializes public therapist fields" do
    therapist = create(:therapist)

    json = TherapistBlueprint.render_as_hash(therapist)

    expect(json).to include(
      id: therapist.id,
      user_id: therapist.user_id,
      license_type: therapist.license_type,
      specialties: therapist.specialties,
      preferences: therapist.preferences,
      slug: therapist.slug
    )
  end
end

