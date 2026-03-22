# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Document Upload", type: :request do
  describe "POST /api/agent/documents/upload" do
    let(:user) { create(:user, :client) }
    let(:headers) { auth_headers_for(user) }
    let(:file) do
      Rack::Test::UploadedFile.new(
        StringIO.new("fake image data"),
        "image/jpeg",
        true,
        original_filename: "insurance_card.jpg"
      )
    end

    it "accepts multipart upload with valid auth" do
      post "/api/agent/documents/upload",
        params: { file: file, document_type: "insurance_card" },
        headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "returns document_ref on success" do
      post "/api/agent/documents/upload",
        params: { file: file, document_type: "insurance_card" },
        headers: headers

      json = JSON.parse(response.body)
      expect(json).to have_key("document_ref")
      expect(json["document_ref"]).to match(/\A[0-9a-f\-]{36}\z/)
      expect(json["status"]).to eq("verified")
      expect(json["fields"]).to be_an(Array)
      expect(json["redacted_preview"]).to be_present
    end

    it "rejects unauthenticated uploads" do
      post "/api/agent/documents/upload",
        params: { file: file }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects uploads without file" do
      post "/api/agent/documents/upload",
        params: { document_type: "insurance_card" },
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("File is required")
    end
  end
end
