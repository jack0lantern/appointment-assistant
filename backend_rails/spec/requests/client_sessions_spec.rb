# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/my/sessions", type: :request do
  it "requires authentication" do
    get "/api/my/sessions"

    expect(response).to have_http_status(:unauthorized)
  end

  context "with authenticated client" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:user) { client.user }
    let(:headers) { auth_headers_for(user) }

    it "returns the client's sessions ordered by date descending" do
      older = create(:session, therapist: therapist, client: client, session_date: 2.days.ago, session_number: 1)
      newer = create(:session, therapist: therapist, client: client, session_date: 1.day.ago, session_number: 2)

      get "/api/my/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.length).to eq(2)
      expect(json.first["id"]).to eq(newer.id)
      expect(json.first["session_number"]).to eq(2)
      expect(json.second["id"]).to eq(older.id)
    end

    it "excludes sessions belonging to other clients" do
      other_client = create(:client, therapist: therapist)
      create(:session, therapist: therapist, client: other_client, session_date: 1.day.ago)
      my_session = create(:session, therapist: therapist, client: client, session_date: 2.days.ago)

      get "/api/my/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first["id"]).to eq(my_session.id)
    end

    it "returns empty array when no sessions" do
      get "/api/my/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end

    it "returns 404 when user has no client profile" do
      non_client = create(:user, role: "client")
      headers = auth_headers_for(non_client)

      get "/api/my/sessions", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns only completed sessions, not scheduled appointments" do
      completed = create(:session, therapist: therapist, client: client, session_date: 2.days.ago, status: "completed")
      scheduled = create(:session, :scheduled, therapist: therapist, client: client, session_date: 1.day.from_now, session_number: 2)

      get "/api/my/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first["id"]).to eq(completed.id)
      expect(json.map { |s| s["id"] }).not_to include(scheduled.id)
    end

    it "includes session summary when present" do
      session = create(:session, therapist: therapist, client: client, session_date: 1.day.ago)
      create(:session_summary, session: session, client_summary: "We discussed goals.", key_themes: ["anxiety", "coping"])

      get "/api/my/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first["summary"]).to be_present
      expect(json.first["summary"]["client_summary"]).to eq("We discussed goals.")
      expect(json.first["summary"]["key_themes"]).to eq(["anxiety", "coping"])
    end
  end
end
