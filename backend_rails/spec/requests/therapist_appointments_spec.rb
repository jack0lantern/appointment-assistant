# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/therapist/appointments", type: :request do
  it "requires authentication" do
    get "/api/therapist/appointments"

    expect(response).to have_http_status(:unauthorized)
  end

  context "with authenticated therapist" do
    let(:therapist) { create(:therapist) }
    let(:user) { therapist.user }
    let(:headers) { auth_headers_for(user) }

    it "returns only upcoming scheduled appointments" do
      client1 = create(:client, therapist: therapist)
      client2 = create(:client, therapist: therapist)

      upcoming = create(:session, :scheduled, therapist: therapist, client: client1, session_date: 1.day.from_now)
      past = create(:session, :scheduled, therapist: therapist, client: client2, session_date: 1.day.ago)

      get "/api/therapist/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"]).to be_an(Array)
      expect(json["appointments"].length).to eq(1)
      expect(json["appointments"].first["session_id"]).to eq(upcoming.id)
      expect(json["appointments"].first["client_name"]).to eq(client1.name)
      expect(json["appointments"]).not_to include(hash_including("session_id" => past.id))
    end

    it "excludes completed and cancelled sessions" do
      client = create(:client, therapist: therapist)
      create(:session, therapist: therapist, client: client, status: "completed", session_date: 1.day.from_now)
      create(:session, therapist: therapist, client: client, status: "cancelled", session_date: 1.day.from_now)

      get "/api/therapist/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"]).to eq([])
    end

    it "returns empty array when no upcoming appointments" do
      get "/api/therapist/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"]).to eq([])
    end

    it "returns 404 when user has no therapist profile" do
      non_therapist = create(:user, role: "therapist")
      headers = auth_headers_for(non_therapist)

      get "/api/therapist/appointments", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
