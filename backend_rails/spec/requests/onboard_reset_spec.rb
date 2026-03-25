# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/onboard/:slug/reset", type: :request do
  let(:therapist_user) { create(:user, :therapist, name: "Dr. Sarah Chen") }
  let(:therapist) { create(:therapist, user: therapist_user, slug: "sarah-chen") }
  let(:client_user) { create(:user, :client, name: "Test Client") }

  describe "authentication" do
    it "requires auth" do
      therapist # ensure exists
      post "/api/onboard/#{therapist.slug}/reset"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "with valid auth" do
    it "returns 404 for invalid slug" do
      post "/api/onboard/nonexistent-slug/reset", headers: auth_headers_for(client_user)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Therapist not found")
    end

    it "clears messages and resets onboarding progress while keeping referral therapist" do
      therapist # ensure exists
      get "/api/onboard/#{therapist.slug}", headers: auth_headers_for(client_user)
      conversation = client_user.conversations.find_by!(context_type: "onboarding")
      conversation.messages.create!(role: "user", content: "hello")
      conversation.messages.create!(role: "assistant", content: "hi")
      conversation.save_onboarding!(
        OnboardingProgress.new(
          assigned_therapist_id: therapist.id,
          has_completed_intake: true,
          docs_verified: true
        )
      )

      post "/api/onboard/#{therapist.slug}/reset", headers: auth_headers_for(client_user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["conversation_id"]).to eq(conversation.uuid)
      expect(body["therapist_name"]).to eq("Dr. Sarah Chen")

      conversation.reload
      expect(conversation.messages.count).to eq(0)
      progress = conversation.onboarding
      expect(progress.assigned_therapist_id).to eq(therapist.id)
      expect(progress.has_completed_intake).to be(false)
      expect(progress.docs_verified).to be(false)
    end

    it "creates a fresh onboarding conversation when none exists" do
      therapist # ensure exists
      expect(client_user.conversations.where(context_type: "onboarding").count).to eq(0)

      post "/api/onboard/#{therapist.slug}/reset", headers: auth_headers_for(client_user)

      expect(response).to have_http_status(:ok)
      expect(client_user.conversations.where(context_type: "onboarding").count).to eq(1)
      conv = client_user.conversations.find_by!(context_type: "onboarding")
      expect(conv.onboarding.assigned_therapist_id).to eq(therapist.id)
    end
  end
end
