# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/my/homework", type: :request do
  it "requires authentication" do
    get "/api/my/homework"

    expect(response).to have_http_status(:unauthorized)
  end

  context "with authenticated client" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:user) { client.user }
    let(:headers) { auth_headers_for(user) }

    it "returns homework items for the current client" do
      plan = create(:treatment_plan, client: client, therapist: therapist)
      version = create(:treatment_plan_version, treatment_plan: plan)
      item = create(:homework_item, client: client, treatment_plan_version: version, description: "Practice mindfulness")

      get "/api/my/homework", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.length).to eq(1)
      expect(json.first["id"]).to eq(item.id)
      expect(json.first["description"]).to eq("Practice mindfulness")
      expect(json.first["completed"]).to eq(false)
      expect(json.first).to have_key("completed_at")
    end

    it "returns only homework for the current client" do
      other_client = create(:client, therapist: therapist)
      other_plan = create(:treatment_plan, client: other_client, therapist: therapist)
      other_version = create(:treatment_plan_version, treatment_plan: other_plan)
      create(:homework_item, client: other_client, treatment_plan_version: other_version)

      my_plan = create(:treatment_plan, client: client, therapist: therapist)
      my_version = create(:treatment_plan_version, treatment_plan: my_plan)
      my_item = create(:homework_item, client: client, treatment_plan_version: my_version)

      get "/api/my/homework", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first["id"]).to eq(my_item.id)
    end

    it "returns empty array when no homework" do
      get "/api/my/homework", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "returns 404 when user has no client profile" do
      non_client = create(:user, role: "client")
      get "/api/my/homework", headers: auth_headers_for(non_client)

      expect(response).to have_http_status(:not_found)
    end
  end
end

RSpec.describe "PATCH /api/homework/:id", type: :request do
  it "requires authentication" do
    patch "/api/homework/1", params: { completed: true }

    expect(response).to have_http_status(:unauthorized)
  end

  context "with authenticated client" do
    let(:therapist) { create(:therapist) }
    let(:client) { create(:client, therapist: therapist) }
    let(:user) { client.user }
    let(:headers) { auth_headers_for(user) }

    it "marks homework as completed" do
      plan = create(:treatment_plan, client: client, therapist: therapist)
      version = create(:treatment_plan_version, treatment_plan: plan)
      item = create(:homework_item, client: client, treatment_plan_version: version, completed: false)

      patch "/api/homework/#{item.id}", params: { completed: true }, headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["completed"]).to eq(true)
      expect(json["completed_at"]).to be_present
      expect(item.reload.completed).to eq(true)
      expect(item.reload.completed_at).to be_present
    end

    it "returns 404 when homework belongs to another client" do
      other_client = create(:client, therapist: therapist)
      other_plan = create(:treatment_plan, client: other_client, therapist: therapist)
      other_version = create(:treatment_plan_version, treatment_plan: other_plan)
      other_item = create(:homework_item, client: other_client, treatment_plan_version: other_version)

      patch "/api/homework/#{other_item.id}", params: { completed: true }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(other_item.reload.completed).to eq(false)
    end

    it "returns 404 when user has no client profile" do
      non_client = create(:user, role: "client")
      plan = create(:treatment_plan, client: client, therapist: therapist)
      version = create(:treatment_plan_version, treatment_plan: plan)
      item = create(:homework_item, client: client, treatment_plan_version: version)

      patch "/api/homework/#{item.id}", params: { completed: true }, headers: auth_headers_for(non_client)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when homework item does not exist" do
      patch "/api/homework/99999", params: { completed: true }, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
