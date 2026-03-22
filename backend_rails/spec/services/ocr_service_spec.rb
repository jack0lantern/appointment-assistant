require "rails_helper"

RSpec.describe OcrService do
  subject(:service) { described_class.new }

  describe "#extract_text" do
    it "returns a non-empty string" do
      result = service.extract_text("fake-image-data", "card.jpg")
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe "#extract_fields" do
    it "finds name" do
      text = "Patient Name: John Smith\nDOB: 01/15/1990\nPolicy Number: ABC123456"
      fields = service.extract_fields(text)
      names = fields.select { |f| f.field_name == "name" }
      expect(names.size).to eq(1)
      expect(names.first.value).to include("John Smith")
    end

    it "finds date of birth" do
      text = "Name: Jane Doe\nDate of Birth: 03/22/1985"
      fields = service.extract_fields(text)
      dob = fields.select { |f| f.field_name == "date_of_birth" }
      expect(dob.size).to eq(1)
      expect(dob.first.value).to include("03/22/1985")
    end

    it "finds policy number" do
      text = "Member ID: XYZ-987654\nGroup: GRP-001"
      fields = service.extract_fields(text)
      policy = fields.select { |f| f.field_name == "policy_number" }
      expect(policy.size).to eq(1)
    end
  end

  describe "#redact_for_llm" do
    it "masks PII" do
      text = "Patient: John Smith, email: john@test.com, SSN: 123-45-6789"
      redacted = service.redact_for_llm(text)
      expect(redacted).not_to include("John Smith")
      expect(redacted).not_to include("john@test.com")
      expect(redacted).not_to include("123-45-6789")
    end
  end

  describe "#process_document" do
    it "returns all expected fields" do
      result = service.process_document("data", "test.jpg", "insurance_card")
      expect(result).to have_key(:raw_text)
      expect(result).to have_key(:redacted_preview)
      expect(result).to have_key(:fields)
    end
  end

  describe "redaction integration" do
    it "accepts a shared redactor" do
      redactor = RedactionService.new
      service_with_redactor = described_class.new(redactor: redactor)
      expect(service_with_redactor.redactor).to eq(redactor)
    end

    it "redacted output has no raw PII" do
      text = "Name: Jane Doe\nPhone: (555) 123-4567\nPolicy: POL-12345678"
      redacted = service.redact_for_llm(text)
      expect(redacted).not_to include("(555) 123-4567")
    end
  end
end
