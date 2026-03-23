# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Scheduling", type: :request do
  describe "GET /api/agent/scheduling/availability" do
    it "requires authentication" do
      get "/api/agent/scheduling/availability", params: { therapist_id: 1 }

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated client" do
      let(:user) { create(:user, :client) }
      let(:headers) { auth_headers_for(user) }
      let(:therapist) { create(:therapist) }

      it "returns available slots" do
        get "/api/agent/scheduling/availability",
            params: { therapist_id: therapist.id },
            headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to have_key("slots")
        expect(json["slots"]).to be_an(Array)
        expect(json["slots"].length).to be > 0
      end

      it "returns 404 for non-existent therapist" do
        get "/api/agent/scheduling/availability",
            params: { therapist_id: 99999 },
            headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "requires therapist_id param" do
        get "/api/agent/scheduling/availability", headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /api/agent/scheduling/book" do
    it "requires authentication" do
      post "/api/agent/scheduling/book",
           params: { therapist_id: 1, slot_id: "1:2026-03-24T19:00:00Z" },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated client" do
      let(:therapist) { create(:therapist) }
      let(:user) { create(:user, :client) }
      let!(:client) { create(:client, user: user, therapist: therapist) }
      let(:headers) { auth_headers_for(user) }
      let(:slot_id) { SchedulingService.get_availability(therapist_id: therapist.id).first[:id] }

      it "books an appointment" do
        post "/api/agent/scheduling/book",
             params: { therapist_id: therapist.id, slot_id: slot_id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("confirmed")
        expect(json["session_id"]).to be_present
      end

      it "requires therapist_id and slot_id" do
        post "/api/agent/scheduling/book",
             params: { therapist_id: therapist.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with authenticated therapist" do
      let(:therapist) { create(:therapist) }
      let(:user) { therapist.user }
      let!(:client) { create(:client, therapist: therapist) }
      let(:headers) { auth_headers_for(user) }
      let(:slot_id) { SchedulingService.get_availability(therapist_id: therapist.id).first[:id] }

      it "books on behalf of a client" do
        post "/api/agent/scheduling/book",
             params: {
               therapist_id: therapist.id,
               slot_id: slot_id,
               client_id: client.id
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("confirmed")
      end

      it "requires client_id for therapist delegation" do
        post "/api/agent/scheduling/book",
             params: { therapist_id: therapist.id, slot_id: slot_id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "POST /api/agent/scheduling/cancel" do
    it "requires authentication" do
      post "/api/agent/scheduling/cancel",
           params: { session_id: 1 },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated client" do
      let(:therapist) { create(:therapist) }
      let(:user) { create(:user, :client) }
      let!(:client) { create(:client, user: user, therapist: therapist) }
      let(:headers) { auth_headers_for(user) }
      let!(:session) do
        create(:session, client: client, therapist: therapist, status: "scheduled")
      end

      it "cancels an appointment" do
        post "/api/agent/scheduling/cancel",
             params: { session_id: session.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("cancelled")
        expect(json["session_id"]).to eq(session.id)
      end

      it "requires session_id" do
        post "/api/agent/scheduling/cancel",
             params: {},
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with authenticated therapist" do
      let(:therapist) { create(:therapist) }
      let(:user) { therapist.user }
      let!(:client) { create(:client, therapist: therapist) }
      let(:headers) { auth_headers_for(user) }
      let!(:session) do
        create(:session, client: client, therapist: therapist, status: "scheduled")
      end

      it "cancels on behalf of a client" do
        post "/api/agent/scheduling/cancel",
             params: { session_id: session.id, client_id: client.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("cancelled")
      end

      it "requires client_id for therapist delegation" do
        post "/api/agent/scheduling/cancel",
             params: { session_id: session.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
