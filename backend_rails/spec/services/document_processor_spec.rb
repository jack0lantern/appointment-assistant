# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentProcessorService do
  subject(:service) { described_class.new }

  let(:valid_file_data) { "fake image binary content" }
  let(:valid_filename) { "insurance_card.jpg" }
  let(:document_type) { "insurance_card" }

  describe "#process" do
    it "extracts fields from insurance card OCR" do
      result = service.process(
        file_data: valid_file_data,
        filename: valid_filename,
        document_type: document_type
      )

      expect(result[:status]).to eq("verified")
      expect(result[:fields]).to be_an(Array)
      expect(result[:fields].length).to be > 0

      field_names = result[:fields].map { |f| f[:field_name] }
      expect(field_names).to include("name")
      expect(field_names).to include("policy_number")
    end

    it "redacts PII before storing in conversation" do
      result = service.process(
        file_data: valid_file_data,
        filename: valid_filename,
        document_type: document_type
      )

      expect(result[:redacted_preview]).not_to include("Demo Patient")
      expect(result[:redacted_preview]).to include("[NAME_1]")
    end

    it "sets docs_verified after successful processing" do
      user = create(:user, :client)
      conversation = create(:conversation, :onboarding, user: user, onboarding_progress: { docs_verified: false })

      service.process(
        file_data: valid_file_data,
        filename: valid_filename,
        document_type: document_type,
        conversation: conversation
      )

      conversation.reload
      expect(conversation.onboarding.docs_verified).to eq(true)
    end

    it "stores raw OCR server-side only" do
      result = service.process(
        file_data: valid_file_data,
        filename: valid_filename,
        document_type: document_type
      )

      # raw_text is returned for server-side storage but must not go to LLM
      expect(result[:raw_text]).to be_present
      expect(result[:raw_text]).to include("Demo Patient")
      # redacted_preview is the safe version
      expect(result[:redacted_preview]).not_to include("Demo Patient")
    end

    it "handles invalid file types gracefully" do
      expect {
        service.process(
          file_data: "malicious content",
          filename: "malware.exe",
          document_type: document_type
        )
      }.to raise_error(DocumentProcessorService::InvalidFileTypeError, /not allowed/)

      expect {
        service.process(
          file_data: "zip content",
          filename: "archive.zip",
          document_type: document_type
        )
      }.to raise_error(DocumentProcessorService::InvalidFileTypeError, /not allowed/)
    end

    it "rejects files exceeding size limit" do
      oversized_data = "x" * (11 * 1024 * 1024) # 11 MB

      expect {
        service.process(
          file_data: oversized_data,
          filename: "large_scan.png",
          document_type: document_type
        )
      }.to raise_error(DocumentProcessorService::FileTooLargeError, /exceeds maximum size/)
    end

    it "stores document_ref and redacted_preview in onboarding when conversation is present" do
      user = create(:user, :client)
      conversation = create(:conversation, :onboarding, user: user, onboarding_progress: {})

      result = service.process(
        file_data: valid_file_data,
        filename: valid_filename,
        document_type: document_type,
        conversation: conversation
      )

      conversation.reload
      progress = conversation.onboarding
      expect(progress.uploaded_documents).to be_an(Array)
      expect(progress.uploaded_documents.length).to eq(1)
      doc = progress.uploaded_documents.first
      expect(doc[:document_ref]).to eq(result[:document_ref])
      expect(doc[:redacted_preview]).to eq(result[:redacted_preview])
      expect(doc[:status]).to eq("verified")
    end
  end
end
