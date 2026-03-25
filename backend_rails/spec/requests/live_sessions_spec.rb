# frozen_string_literal: true

require "rails_helper"
require "jwt"

RSpec.describe "Live sessions API", type: :request do
  describe "POST /api/clients/:client_id/sessions/live" do
    it "requires authentication" do
      post "/api/clients/1/sessions/live", params: { duration_minutes: 50 }

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated therapist" do
      let(:therapist) { create(:therapist) }
      let(:user) { therapist.user }
      let(:headers) { auth_headers_for(user) }

      it "returns 404 when client is not found" do
        post "/api/clients/999_999/sessions/live", params: { duration_minutes: 50 }, headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 when client belongs to another therapist" do
        other = create(:therapist)
        client = create(:client, therapist: other)

        post "/api/clients/#{client.id}/sessions/live", params: { duration_minutes: 50 }, headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "creates an in_progress live session and sets livekit room name" do
        client = create(:client, therapist: therapist, user: nil)

        post "/api/clients/#{client.id}/sessions/live", params: { duration_minutes: 50 }, headers: headers

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json["session_type"]).to eq("live")
        expect(json["status"]).to eq("in_progress")
        expect(json["duration_minutes"]).to eq(50)
        expect(json["livekit_room_name"]).to eq("appt-session-#{json['id']}")

        session = Session.find(json["id"])
        expect(session.livekit_room_name).to eq("appt-session-#{session.id}")
      end
    end

    context "with authenticated client (no therapist profile)" do
      let(:therapist) { create(:therapist) }
      let(:client) { create(:client, therapist: therapist) }
      let(:headers) { auth_headers_for(client.user) }

      it "returns 404" do
        post "/api/clients/#{client.id}/sessions/live", params: { duration_minutes: 50 }, headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/sessions/:session_id/live/token" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:session) do
      create(
        :session,
        therapist: therapist,
        client: client,
        status: "in_progress",
        session_type: "live",
        livekit_room_name: "appt-session-999",
        session_date: Time.current,
      )
    end

    it "requires authentication" do
      post "/api/sessions/#{session.id}/live/token"

      expect(response).to have_http_status(:unauthorized)
    end

    context "with session therapist" do
      let(:headers) { auth_headers_for(therapist.user) }

      it "returns a LiveKit JWT and server URL" do
        post "/api/sessions/#{session.id}/live/token", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["token"]).to be_present
        expect(json["room_name"]).to eq("appt-session-999")
        expect(json["server_url"]).to eq(LivekitTokenService.server_url)
        expect(json["peer_name"]).to eq(client.name)

        payload, = JWT.decode(
          json["token"],
          LivekitTokenService.api_secret,
          true,
          { algorithm: "HS256" },
        )
        expect(payload["video"]["room"]).to eq("appt-session-999")
        expect(payload["video"]["roomJoin"]).to be true
      end
    end

    context "with session client user" do
      let(:headers) { auth_headers_for(client.user) }

      it "returns token with therapist name as peer" do
        post "/api/sessions/#{session.id}/live/token", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["peer_name"]).to eq(therapist.user.name)
      end
    end

    it "returns 403 for another therapist" do
      other = create(:therapist)
      headers = auth_headers_for(other.user)

      post "/api/sessions/#{session.id}/live/token", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for unknown session" do
      headers = auth_headers_for(therapist.user)

      post "/api/sessions/0/live/token", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/sessions/:session_id/live/end" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:session) do
      create(
        :session,
        therapist: therapist,
        client: client,
        status: "in_progress",
        session_type: "live",
        livekit_room_name: "appt-session-#{SecureRandom.hex(4)}",
        session_date: Time.current,
      )
    end

    it "requires authentication" do
      post "/api/sessions/#{session.id}/live/end"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 for unknown session" do
      headers = auth_headers_for(therapist.user)

      post "/api/sessions/0/live/end", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 403 for another therapist" do
      other = create(:therapist)
      headers = auth_headers_for(other.user)

      post "/api/sessions/#{session.id}/live/end", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    context "with session therapist" do
      let(:headers) { auth_headers_for(therapist.user) }

      it "marks the live session completed and returns no content" do
        post "/api/sessions/#{session.id}/live/end", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(session.reload.status).to eq("completed")
      end

      it "is idempotent when already completed" do
        session.update!(status: "completed")

        post "/api/sessions/#{session.id}/live/end", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(session.reload.status).to eq("completed")
      end
    end

    context "with session client user" do
      let(:headers) { auth_headers_for(client.user) }

      it "marks the live session completed" do
        post "/api/sessions/#{session.id}/live/end", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(session.reload.status).to eq("completed")
      end
    end
  end
end
