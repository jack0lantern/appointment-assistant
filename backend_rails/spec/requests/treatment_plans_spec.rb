# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Treatment plans API", type: :request do
  let(:therapist) { create(:therapist) }
  let(:user) { therapist.user }
  let(:headers) { auth_headers_for(user) }

  describe "POST /api/treatment-plans/:id/approve" do
    it "requires authentication" do
      post "/api/treatment-plans/1/approve"

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated therapist" do
      let(:client) { create(:client, therapist: therapist) }
      let(:plan) { create(:treatment_plan, client: client, therapist: therapist, status: "draft") }
      let(:version) do
        create(
          :treatment_plan_version,
          treatment_plan: plan,
          version_number: 1,
          therapist_content: { "goals" => [] },
          client_content: { "your_goals" => ["Rest"] },
        )
      end

      before { plan.update!(current_version_id: version.id) }

      it "approves when there are no safety flags" do
        post "/api/treatment-plans/#{plan.id}/approve", headers: headers

        expect(response).to have_http_status(:ok)
        expect(plan.reload.status).to eq("approved")
      end

      it "approves when all safety flags are acknowledged" do
        session = create(:session, therapist: therapist, client: client)
        create(:safety_flag, session: session, acknowledged: true)

        post "/api/treatment-plans/#{plan.id}/approve", headers: headers

        expect(response).to have_http_status(:ok)
        expect(plan.reload.status).to eq("approved")
      end

      it "returns 422 when a safety flag is not acknowledged" do
        session = create(:session, therapist: therapist, client: client)
        create(:safety_flag, session: session, acknowledged: false)

        post "/api/treatment-plans/#{plan.id}/approve", headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json["error"]).to be_present
        expect(plan.reload.status).to eq("draft")
      end

      it "returns 404 when plan belongs to another therapist" do
        other = create(:treatment_plan)

        post "/api/treatment-plans/#{other.id}/approve", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/treatment-plans/:id/edit" do
    let(:client) { create(:client, therapist: therapist) }
    let(:plan) { create(:treatment_plan, client: client, therapist: therapist) }
    let(:version) do
      create(
        :treatment_plan_version,
        treatment_plan: plan,
        version_number: 1,
        therapist_content: { "goals" => [{ "description" => "A" }] },
        client_content: { "your_goals" => ["Sleep"] },
      )
    end

    before { plan.update!(current_version_id: version.id) }

    it "creates a new version and sets it as current" do
      new_content = { "goals" => [{ "description" => "B", "modality" => "CBT" }] }

      post "/api/treatment-plans/#{plan.id}/edit",
           params: { therapist_content: new_content, change_summary: "Updated goals" },
           as: :json,
           headers: headers

      expect(response).to have_http_status(:ok)
      plan.reload
      expect(plan.versions.count).to eq(2)
      expect(plan.current_version.version_number).to eq(2)
      expect(plan.current_version.therapist_content).to include("goals")
      expect(plan.current_version.source).to eq("therapist_edit")
    end
  end

  describe "GET /api/treatment-plans/:id/versions" do
    let(:client) { create(:client, therapist: therapist) }
    let(:plan) { create(:treatment_plan, client: client, therapist: therapist) }

    it "returns version summaries" do
      v = create(:treatment_plan_version, treatment_plan: plan, version_number: 1, change_summary: "v1")

      get "/api/treatment-plans/#{plan.id}/versions", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.first["version_number"]).to eq(v.version_number)
      expect(json.first["id"]).to eq(v.id)
    end
  end

  describe "GET /api/treatment-plans/:id/diff" do
    let(:client) { create(:client, therapist: therapist) }
    let(:plan) { create(:treatment_plan, client: client, therapist: therapist) }

    it "returns structured diffs between two version numbers" do
      create(
        :treatment_plan_version,
        treatment_plan: plan,
        version_number: 1,
        therapist_content: { "goals" => [{ "description" => "Old" }] },
      )
      create(
        :treatment_plan_version,
        treatment_plan: plan,
        version_number: 2,
        therapist_content: { "goals" => [{ "description" => "New" }] },
      )

      get "/api/treatment-plans/#{plan.id}/diff?v1=1&v2=2", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["diffs"]).to be_a(Hash)
      expect(json["diffs"]["goals"]["status"]).to eq("modified")
    end
  end

  describe "GET /api/treatment-plans/draft" do
    it "returns draft plans for the therapist" do
      client = create(:client, therapist: therapist)
      plan = create(:treatment_plan, client: client, therapist: therapist, status: "draft")

      get "/api/treatment-plans/draft", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.first["plan_id"]).to eq(plan.id)
      expect(json.first["client_name"]).to eq(client.name)
    end
  end
end
