require "rails_helper"

RSpec.describe RedactionService do
  subject(:redactor) { described_class.new }

  # ── Email detection ──────────────────────────────────────────────────

  describe "email redaction" do
    it "redacts email addresses" do
      result = redactor.redact("Contact me at john.doe@example.com please")
      expect(result.redacted_text).not_to include("john.doe@example.com")
      expect(result.redacted_text).to include("[EMAIL_")
      expect(result.mappings.size).to eq(1)
    end

    it "redacts multiple emails" do
      result = redactor.redact("Email a@b.com or c@d.org")
      expect(result.redacted_text).not_to include("a@b.com")
      expect(result.redacted_text).not_to include("c@d.org")
      expect(result.mappings.size).to eq(2)
    end
  end

  # ── Phone number detection ───────────────────────────────────────────

  describe "phone redaction" do
    it "redacts US phone with parens" do
      result = redactor.redact("Call me at (555) 123-4567")
      expect(result.redacted_text).not_to include("(555) 123-4567")
      expect(result.redacted_text).to include("[PHONE_")
    end

    it "redacts phone with dashes" do
      result = redactor.redact("My number is 555-123-4567")
      expect(result.redacted_text).not_to include("555-123-4567")
    end

    it "redacts phone with dots" do
      result = redactor.redact("Reach me at 555.123.4567")
      expect(result.redacted_text).not_to include("555.123.4567")
    end
  end

  # ── SSN detection ────────────────────────────────────────────────────

  describe "SSN redaction" do
    it "redacts SSN with dashes" do
      result = redactor.redact("SSN: 123-45-6789")
      expect(result.redacted_text).not_to include("123-45-6789")
      expect(result.redacted_text).to include("[SSN_")
    end

    it "redacts SSN without dashes" do
      result = redactor.redact("SSN 123456789 on file")
      expect(result.redacted_text).not_to include("123456789")
    end
  end

  # ── Name detection (contextual) ──────────────────────────────────────

  describe "name redaction" do
    it "redacts name with prefix" do
      result = redactor.redact("Patient name: John Smith")
      expect(result.redacted_text).not_to include("John Smith")
      expect(result.redacted_text).to include("[NAME_")
    end

    it "redacts 'my name is' pattern" do
      result = redactor.redact("My name is Jane Doe")
      expect(result.redacted_text).not_to include("Jane Doe")
    end
  end

  # ── Address detection ────────────────────────────────────────────────

  describe "address redaction" do
    it "redacts street address" do
      result = redactor.redact("I live at 123 Main Street, Springfield IL 62704")
      expect(result.redacted_text).not_to include("123 Main Street")
      expect(result.redacted_text).to include("[ADDRESS_")
    end
  end

  # ── Date of birth ────────────────────────────────────────────────────

  describe "DOB redaction" do
    it "redacts DOB with label" do
      result = redactor.redact("DOB: 01/15/1990")
      expect(result.redacted_text).not_to include("01/15/1990")
      expect(result.redacted_text).to include("[DOB_")
    end

    it "redacts date of birth with full label" do
      result = redactor.redact("date of birth: 1990-01-15")
      expect(result.redacted_text).not_to include("1990-01-15")
    end
  end

  # ── Insurance / policy numbers ───────────────────────────────────────

  describe "policy number redaction" do
    it "redacts policy number" do
      result = redactor.redact("Policy number: ABC123456789")
      expect(result.redacted_text).not_to include("ABC123456789")
      expect(result.redacted_text).to include("[POLICY_")
    end

    it "redacts member ID" do
      result = redactor.redact("Member ID: XYZ-987654")
      expect(result.redacted_text).not_to include("XYZ-987654")
    end
  end

  # ── Stable token mapping ─────────────────────────────────────────────

  describe "stable token mapping" do
    it "gives same value same token" do
      result = redactor.redact("Email john@test.com and again john@test.com")
      unique_originals = result.mappings.map(&:original).uniq
      expect(unique_originals.size).to eq(1)
    end

    it "allows restore from tokens" do
      result = redactor.redact("Contact john@test.com")
      restored = redactor.restore(result.redacted_text)
      expect(restored).to include("john@test.com")
    end

    it "restores multiple PII types" do
      text = "Name: John Smith, email: john@test.com, phone: 555-123-4567"
      result = redactor.redact(text)
      restored = redactor.restore(result.redacted_text)
      expect(restored).to include("john@test.com")
    end
  end

  # ── Edge cases ───────────────────────────────────────────────────────

  describe "edge cases" do
    it "handles empty string" do
      result = redactor.redact("")
      expect(result.redacted_text).to eq("")
      expect(result.mappings).to be_empty
    end

    it "returns text unchanged when no PII present" do
      text = "I feel anxious about my upcoming appointment"
      result = redactor.redact(text)
      expect(result.redacted_text).to eq(text)
      expect(result.mappings).to be_empty
    end

    it "preserves clinical content" do
      text = "Patient reports feeling hopeless and having trouble sleeping for 3 weeks"
      result = redactor.redact(text)
      expect(result.redacted_text).to include("hopeless")
      expect(result.redacted_text).to include("trouble sleeping")
      expect(result.redacted_text).to include("3 weeks")
    end
  end

  # ── Field allowlist ──────────────────────────────────────────────────

  describe "field allowlist" do
    it "keeps only allowed fields" do
      data = { "age" => 35, "name" => "John Smith", "symptoms" => "anxiety" }
      allowed = Set.new(%w[age symptoms])
      filtered = redactor.filter_fields(data, allowed)
      expect(filtered).to eq({ "age" => 35, "symptoms" => "anxiety" })
    end

    it "removes disallowed fields" do
      data = { "name" => "John", "email" => "j@t.com", "concern" => "stress" }
      allowed = Set.new(%w[concern])
      filtered = redactor.filter_fields(data, allowed)
      expect(filtered).not_to have_key("name")
      expect(filtered).not_to have_key("email")
      expect(filtered).to eq({ "concern" => "stress" })
    end
  end
end
