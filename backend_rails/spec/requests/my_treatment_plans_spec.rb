# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/my/treatment-plan", type: :request do
  it "requires authentication" do
    get "/api/my/treatment-plan"

    expect(response).to have_http_status(:unauthorized)
  end

  context "with authenticated client" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:user) { client.user }
    let(:headers) { auth_headers_for(user) }

    it "returns 404 when plan is not approved" do
      plan = create(:treatment_plan, client: client, therapist: therapist, status: "draft")
      version = create(:treatment_plan_version, treatment_plan: plan)
      plan.update!(current_version_id: version.id)

      get "/api/my/treatment-plan", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns the plan when approved" do
      plan = create(:treatment_plan, client: client, therapist: therapist, status: "approved")
      version = create(
        :treatment_plan_version,
        treatment_plan: plan,
        therapist_content: { "goals" => [] },
        client_content: { "what_we_talked_about" => "Hi", "your_goals" => [], "things_to_try" => [], "your_strengths" => [] },
      )
      plan.update!(current_version_id: version.id)

      get "/api/my/treatment-plan", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["plan"]).to be_present
      expect(json["plan"]["status"]).to eq("approved")
      expect(json["plan"]["current_version"]["client_content"]).to be_present
    end
  end
end
