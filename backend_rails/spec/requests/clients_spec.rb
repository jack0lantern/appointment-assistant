# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Clients API", type: :request do
  describe "GET /api/clients" do
    it "requires authentication" do
      get "/api/clients"

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated therapist" do
      let(:therapist) { create(:therapist) }
      let(:user) { therapist.user }
      let(:headers) { auth_headers_for(user) }

      it "includes session_count and last_session_date from completed sessions" do
        client = create(:client, therapist: therapist, name: "Alex Rivera")
        older = 2.days.ago.change(usec: 0)
        newer = 1.day.ago.change(usec: 0)
        create(:session, therapist: therapist, client: client, session_number: 1, session_date: older, status: "completed")
        create(:session, therapist: therapist, client: client, session_number: 2, session_date: newer, status: "completed")
        create(:session, :scheduled, therapist: therapist, client: client, session_number: 3)

        get "/api/clients", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json).to be_an(Array)
        row = json.find { |c| c["id"] == client.id }
        expect(row).to be_present
        expect(row["session_count"]).to eq(2)
        expect(Time.zone.parse(row["last_session_date"])).to eq(newer)
      end

      it "returns zero sessions and nil last date when only scheduled sessions exist" do
        client = create(:client, therapist: therapist)
        create(:session, :scheduled, therapist: therapist, client: client, session_number: 1)

        get "/api/clients", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        row = json.find { |c| c["id"] == client.id }
        expect(row["session_count"]).to eq(0)
        expect(row["last_session_date"]).to be_nil
      end
    end
  end

  describe "GET /api/clients/:id" do
    it "requires authentication" do
      get "/api/clients/1"

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated therapist" do
      let(:therapist) { create(:therapist) }
      let(:user) { therapist.user }
      let(:headers) { auth_headers_for(user) }

      it "returns client detail with sessions and treatment plan" do
        client = create(:client, therapist: therapist, user: nil, name: "Jane Doe")
        create(:session, therapist: therapist, client: client, session_number: 1)
        plan = create(:treatment_plan, client: client, therapist: therapist)
        version = create(:treatment_plan_version, treatment_plan: plan, version_number: 1)
        plan.update!(current_version_id: version.id)

        get "/api/clients/#{client.id}", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["client"]).to be_present
        expect(json["client"]["id"]).to eq(client.id)
        expect(json["client"]["name"]).to eq("Jane Doe")
        expect(json["client"]["session_count"]).to eq(1)
        expect(json["client"]["last_session_date"]).to be_present
        expect(json["sessions"]).to be_an(Array)
        expect(json["sessions"].length).to eq(1)
        expect(json["treatment_plan"]).to be_present
        expect(json["treatment_plan"]["status"]).to eq("draft")
        expect(json["safety_flags"]).to be_an(Array)
      end

      it "returns 404 when client does not belong to therapist" do
        other_therapist = create(:therapist)
        other_client = create(:client, therapist: other_therapist)

        get "/api/clients/#{other_client.id}", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 when client does not exist" do
        get "/api/clients/99999", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns only completed sessions, not scheduled appointments" do
        client = create(:client, therapist: therapist, user: nil)
        completed = create(:session, therapist: therapist, client: client, session_number: 1, status: "completed")
        scheduled = create(:session, :scheduled, therapist: therapist, client: client, session_number: 2)

        get "/api/clients/#{client.id}", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["sessions"].length).to eq(1)
        expect(json["sessions"].first["id"]).to eq(completed.id)
        expect(json["sessions"].map { |s| s["id"] }).not_to include(scheduled.id)
      end

      it "returns null treatment_plan when client has no plan" do
        client = create(:client, therapist: therapist, user: nil)

        get "/api/clients/#{client.id}", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["treatment_plan"]).to be_nil
        expect(json["sessions"]).to eq([])
      end
    end
  end
end
