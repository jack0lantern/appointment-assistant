# frozen_string_literal: true

require "rails_helper"

# Evaluation: Document upload flow, status checking, and unverified → verified transitions.
RSpec.describe "Document upload evaluation", type: :service do
  let(:mock_llm) { instance_double(LlmService) }
  let(:service) { AgentService.new(llm_service: mock_llm) }

  # ---------------------------------------------------------------------------
  # upload_document tool
  # ---------------------------------------------------------------------------
  describe "upload_document tool" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    let(:auth) do
      user.reload
      AgentTools::ToolAuthContext.new(
        user_id: user.id, role: "client",
        client_id: client_record.id, therapist_id: therapist.id
      )
    end

    context "when document exists in onboarding progress" do
      before do
        user.conversations.create!(
          context_type: "onboarding", status: "active",
          onboarding_progress: {
            "is_new_user" => true,
            "has_completed_intake" => true,
            "docs_verified" => false,
            "uploaded_documents" => [
              { "document_ref" => "doc-insurance-123", "redacted_preview" => "Insurance: [POLICY_1], Member: [NAME_1]", "status" => "verified" }
            ]
          }
        )
      end

      it "returns found: true with redacted preview and status" do
        result = AgentTools.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "doc-insurance-123" },
          auth_context: auth
        )

        expect(result[:found]).to be true
        expect(result[:redacted_preview]).to be_present
        expect(result[:status]).to eq("verified")
      end

      it "returns redacted content with tokens, not raw PII" do
        result = AgentTools.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "doc-insurance-123" },
          auth_context: auth
        )

        expect(result[:redacted_preview]).to include("[POLICY_1]")
        expect(result[:redacted_preview]).to include("[NAME_1]")
      end
    end

    context "when document_ref does not match" do
      before do
        user.conversations.create!(
          context_type: "onboarding", status: "active",
          onboarding_progress: {
            "is_new_user" => true,
            "has_completed_intake" => true,
            "docs_verified" => false,
            "uploaded_documents" => [
              { "document_ref" => "doc-insurance-123", "redacted_preview" => "Insurance", "status" => "verified" }
            ]
          }
        )
      end

      it "returns error 'Document not found'" do
        result = AgentTools.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "doc-nonexistent-999" },
          auth_context: auth
        )

        expect(result[:error]).to include("Document not found")
      end
    end

    context "when no onboarding conversation exists" do
      it "returns error about no active onboarding conversation" do
        result = AgentTools.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "doc-123" },
          auth_context: auth
        )

        expect(result[:error]).to include("No active onboarding conversation")
      end
    end

    context "when document_ref is blank" do
      before do
        user.conversations.create!(
          context_type: "onboarding", status: "active",
          onboarding_progress: { "is_new_user" => true }
        )
      end

      it "returns error about required document_ref" do
        result = AgentTools.execute_tool(
          name: "upload_document",
          input: { "document_ref" => "" },
          auth_context: auth
        )

        expect(result[:error]).to include("document_ref is required")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # check_document_status tool
  # ---------------------------------------------------------------------------
  describe "check_document_status tool" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    let(:auth) do
      user.reload
      AgentTools::ToolAuthContext.new(
        user_id: user.id, role: "client",
        client_id: client_record.id, therapist_id: therapist.id
      )
    end

    it "returns docs_verified: false when documents not yet uploaded" do
      user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => false }
      )

      result = AgentTools.execute_tool(name: "check_document_status", input: {}, auth_context: auth)

      expect(result[:docs_verified]).to be false
    end

    it "returns docs_verified: true when docs have been verified" do
      user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => true }
      )

      result = AgentTools.execute_tool(name: "check_document_status", input: {}, auth_context: auth)

      expect(result[:docs_verified]).to be true
    end

    it "returns docs_verified: false when no active onboarding conversation" do
      result = AgentTools.execute_tool(name: "check_document_status", input: {}, auth_context: auth)

      expect(result[:docs_verified]).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Document status transition via pipeline
  # ---------------------------------------------------------------------------
  describe "document status transition via pipeline" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    it "scheduling guard blocks when docs_verified: false" do
      user.reload
      user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => false }
      )

      auth = AgentTools::ToolAuthContext.new(
        user_id: user.id, role: "client",
        client_id: client_record.id, therapist_id: therapist.id
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { "therapist_id" => therapist.id },
        auth_context: auth
      )

      expect(result[:error]).to eq("onboarding_incomplete")
      expect(result[:missing_step]).to eq("documents")
    end

    it "scheduling guard allows when docs_verified: true" do
      user.reload
      user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => true }
      )

      auth = AgentTools::ToolAuthContext.new(
        user_id: user.id, role: "client",
        client_id: client_record.id, therapist_id: therapist.id
      )

      result = AgentTools.execute_tool(
        name: "get_available_slots",
        input: { "therapist_id" => therapist.id },
        auth_context: auth
      )

      expect(result).not_to have_key(:error)
      expect(result[:days]).to be_an(Array)
    end

    it "onboarding progress reflects docs_verified after verification" do
      user.reload
      allow(mock_llm).to receive(:call).and_return(
        "content" => [{ "type" => "text", "text" => "Great, your documents are verified!" }]
      )

      conversation = user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: { "is_new_user" => true, "has_completed_intake" => true, "docs_verified" => true }
      )

      service.process_message(
        message: "My documents should be ready now",
        user: user,
        conversation_id: conversation.uuid,
        context_type: "onboarding"
      )

      conversation.reload
      expect(conversation.onboarding.docs_verified).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple document uploads
  # ---------------------------------------------------------------------------
  describe "multiple documents" do
    let(:user) { create(:user, :client) }
    let!(:therapist) { create(:therapist) }
    let!(:client_record) { create(:client, user: user, therapist: therapist) }

    let(:auth) do
      user.reload
      AgentTools::ToolAuthContext.new(
        user_id: user.id, role: "client",
        client_id: client_record.id, therapist_id: therapist.id
      )
    end

    it "supports multiple documents in uploaded_documents array" do
      user.conversations.create!(
        context_type: "onboarding", status: "active",
        onboarding_progress: {
          "is_new_user" => true,
          "has_completed_intake" => true,
          "docs_verified" => false,
          "uploaded_documents" => [
            { "document_ref" => "doc-insurance-1", "redacted_preview" => "Insurance card: [POLICY_1]", "status" => "verified" },
            { "document_ref" => "doc-id-2", "redacted_preview" => "State ID: [NAME_1]", "status" => "verified" }
          ]
        }
      )

      result1 = AgentTools.execute_tool(
        name: "upload_document",
        input: { "document_ref" => "doc-insurance-1" },
        auth_context: auth
      )
      result2 = AgentTools.execute_tool(
        name: "upload_document",
        input: { "document_ref" => "doc-id-2" },
        auth_context: auth
      )

      expect(result1[:found]).to be true
      expect(result2[:found]).to be true
    end
  end
end
