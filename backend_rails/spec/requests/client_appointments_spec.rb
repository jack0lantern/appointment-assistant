# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/my/appointments", type: :request do
  it "requires authentication" do
    get "/api/my/appointments"

    expect(response).to have_http_status(:unauthorized)
  end

  context "with authenticated client" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:user) { client.user }
    let(:headers) { auth_headers_for(user) }

    it "returns only upcoming scheduled appointments for the client" do
      upcoming = create(:session, :scheduled, therapist: therapist, client: client, session_date: 1.day.from_now)
      past = create(:session, :scheduled, therapist: therapist, client: client, session_date: 1.day.ago)

      get "/api/my/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"]).to be_an(Array)
      expect(json["appointments"].length).to eq(1)
      expect(json["appointments"].first["session_id"]).to eq(upcoming.id)
      expect(json["appointments"].first["therapist_name"]).to eq(therapist.user.name)
      expect(json["appointments"]).not_to include(hash_including("session_id" => past.id))
    end

    it "excludes completed and cancelled sessions" do
      create(:session, therapist: therapist, client: client, status: "completed", session_date: 1.day.from_now)
      create(:session, therapist: therapist, client: client, status: "cancelled", session_date: 1.day.from_now)

      get "/api/my/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"]).to eq([])
    end

    it "returns only sessions for the current client" do
      other_client = create(:client, therapist: therapist)
      create(:session, :scheduled, therapist: therapist, client: other_client, session_date: 1.day.from_now)
      my_session = create(:session, :scheduled, therapist: therapist, client: client, session_date: 2.days.from_now)

      get "/api/my/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"].length).to eq(1)
      expect(json["appointments"].first["session_id"]).to eq(my_session.id)
    end

    it "returns empty array when no upcoming appointments" do
      get "/api/my/appointments", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["appointments"]).to eq([])
    end

    it "returns 404 when user has no client profile" do
      non_client = create(:user, role: "client")
      headers = auth_headers_for(non_client)

      get "/api/my/appointments", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
