# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/onboard/:slug", type: :request do
  let(:therapist_user) { create(:user, :therapist, name: "Dr. Sarah Chen") }
  let(:therapist) { create(:therapist, user: therapist_user, slug: "sarah-chen") }
  let(:client_user) { create(:user, :client, name: "Test Client") }

  describe "authentication" do
    it "requires auth" do
      therapist # ensure exists
      get "/api/onboard/#{therapist.slug}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "with valid auth" do
    it "resolves valid slug to therapist and creates conversation" do
      therapist # ensure exists
      get "/api/onboard/#{therapist.slug}", headers: auth_headers_for(client_user)

      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["conversation_id"]).to be_present
      expect(body["therapist_name"]).to eq("Dr. Sarah Chen")
      expect(body["context_type"]).to eq("onboarding")
      expect(body["welcome_message"]).to include("Dr. Sarah Chen")

      # A conversation was created
      expect(client_user.conversations.where(context_type: "onboarding").count).to eq(1)
    end

    it "resumes existing onboarding conversation for same user" do
      therapist # ensure exists
      # First request creates conversation
      get "/api/onboard/#{therapist.slug}", headers: auth_headers_for(client_user)
      first_id = response.parsed_body["conversation_id"]

      # Second request returns same conversation
      get "/api/onboard/#{therapist.slug}", headers: auth_headers_for(client_user)
      second_id = response.parsed_body["conversation_id"]

      expect(second_id).to eq(first_id)
      expect(client_user.conversations.where(context_type: "onboarding").count).to eq(1)
    end

    it "returns 404 for invalid slug" do
      get "/api/onboard/nonexistent-slug", headers: auth_headers_for(client_user)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Therapist not found")
    end

    it "sets assigned_therapist_id in onboarding progress" do
      therapist # ensure exists
      get "/api/onboard/#{therapist.slug}", headers: auth_headers_for(client_user)

      conversation = client_user.conversations.find_by(context_type: "onboarding")
      expect(conversation.onboarding_progress["assigned_therapist_id"]).to eq(therapist.id)
    end
  end
end
