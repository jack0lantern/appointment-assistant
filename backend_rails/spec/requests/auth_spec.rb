# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth", type: :request do
  describe "POST /api/auth/client/login" do
    let(:client_user) { create(:user, role: "client", email: "client@test.com", password: "secret123") }

    it "returns token and user for valid client credentials" do
      post "/api/auth/client/login", params: { email: client_user.email, password: "secret123" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["token"]).to be_present
      expect(json["user"]["id"]).to eq(client_user.id)
      expect(json["user"]["role"]).to eq("client")
    end

    it "rejects therapist user with 403 and clear message" do
      therapist_user = create(:user, role: "therapist", email: "therapist@test.com", password: "secret123")
      post "/api/auth/client/login", params: { email: therapist_user.email, password: "secret123" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("therapist")
    end

    it "rejects invalid credentials with 401" do
      post "/api/auth/client/login", params: { email: client_user.email, password: "wrong" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Invalid email or password")
    end

    it "rejects unknown email with 401" do
      post "/api/auth/client/login", params: { email: "nobody@test.com", password: "secret123" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns needs_onboarding for demo new-patient user" do
      jordan = User.find_or_create_by!(email: OnboardingRouter::DEMO_NEW_PATIENT_EMAIL) do |u|
        u.name = "Jordan Kim"
        u.role = "client"
        u.password = "demo123"
      end
      therapist = create(:therapist, slug: "dr-test")
      Client.find_or_create_by!(user: jordan) { |c| c.therapist = therapist; c.name = "Jordan Kim" }
      # Update therapist slug if client already existed with different therapist
      jordan.client_profile.update!(therapist: therapist) if jordan.client_profile.therapist.slug != "dr-test"

      post "/api/auth/client/login", params: { email: jordan.email, password: "demo123" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["needs_onboarding"]).to be true
      expect(json["onboard_slug"]).to eq("dr-test")
    end

    it "returns needs_onboarding for user without client profile" do
      new_user = create(:user, role: "client", email: "newbie@test.com", password: "secret123")

      post "/api/auth/client/login", params: { email: new_user.email, password: "secret123" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["needs_onboarding"]).to be true
      expect(json).not_to have_key("onboard_slug")
    end

    it "does not return needs_onboarding for returning client" do
      therapist = create(:therapist)
      returning_user = create(:user, role: "client", email: "returning@test.com", password: "secret123")
      create(:client, user: returning_user, therapist: therapist)

      post "/api/auth/client/login", params: { email: returning_user.email, password: "secret123" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).not_to have_key("needs_onboarding")
    end
  end

  describe "POST /api/auth/therapist/login" do
    let(:therapist_user) { create(:user, role: "therapist", email: "therapist@test.com", password: "secret123") }

    it "returns token and user for valid therapist credentials" do
      post "/api/auth/therapist/login", params: { email: therapist_user.email, password: "secret123" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["token"]).to be_present
      expect(json["user"]["id"]).to eq(therapist_user.id)
      expect(json["user"]["role"]).to eq("therapist")
    end

    it "rejects client user with 403 and clear message" do
      client_user = create(:user, role: "client", email: "client@test.com", password: "secret123")
      post "/api/auth/therapist/login", params: { email: client_user.email, password: "secret123" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("client")
    end

    it "rejects invalid credentials with 401" do
      post "/api/auth/therapist/login", params: { email: therapist_user.email, password: "wrong" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Invalid email or password")
    end

    it "rejects unknown email with 401" do
      post "/api/auth/therapist/login", params: { email: "nobody@test.com", password: "secret123" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts admin user (admin uses therapist portal)" do
      admin_user = create(:user, role: "admin", email: "admin@test.com", password: "secret123")
      post "/api/auth/therapist/login", params: { email: admin_user.email, password: "secret123" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]["role"]).to eq("admin")
    end
  end
end
