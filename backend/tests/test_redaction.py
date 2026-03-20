"""Tests for the PII/PHI redaction layer.

Validates that sensitive data is detected, masked with stable tokens,
and that the mapping can restore original values server-side.
"""

import pytest

from app.utils.redaction import RedactionResult, Redactor


class TestRedactor:
    """Core redaction functionality."""

    def setup_method(self):
        self.redactor = Redactor()

    # ── Email detection ──────────────────────────────────────────────────

    def test_redacts_email(self):
        result = self.redactor.redact("Contact me at john.doe@example.com please")
        assert "john.doe@example.com" not in result.redacted_text
        assert "[EMAIL_" in result.redacted_text
        assert len(result.mappings) == 1

    def test_redacts_multiple_emails(self):
        result = self.redactor.redact("Email a@b.com or c@d.org")
        assert "a@b.com" not in result.redacted_text
        assert "c@d.org" not in result.redacted_text
        assert len(result.mappings) == 2

    # ── Phone number detection ───────────────────────────────────────────

    def test_redacts_us_phone(self):
        result = self.redactor.redact("Call me at (555) 123-4567")
        assert "(555) 123-4567" not in result.redacted_text
        assert "[PHONE_" in result.redacted_text

    def test_redacts_phone_with_dashes(self):
        result = self.redactor.redact("My number is 555-123-4567")
        assert "555-123-4567" not in result.redacted_text

    def test_redacts_phone_with_dots(self):
        result = self.redactor.redact("Reach me at 555.123.4567")
        assert "555.123.4567" not in result.redacted_text

    # ── SSN detection ────────────────────────────────────────────────────

    def test_redacts_ssn(self):
        result = self.redactor.redact("SSN: 123-45-6789")
        assert "123-45-6789" not in result.redacted_text
        assert "[SSN_" in result.redacted_text

    def test_redacts_ssn_no_dashes(self):
        result = self.redactor.redact("SSN 123456789 on file")
        assert "123456789" not in result.redacted_text

    # ── Name detection (contextual) ──────────────────────────────────────

    def test_redacts_name_with_prefix(self):
        result = self.redactor.redact("Patient name: John Smith")
        assert "John Smith" not in result.redacted_text
        assert "[NAME_" in result.redacted_text

    def test_redacts_name_my_name_is(self):
        result = self.redactor.redact("My name is Jane Doe")
        assert "Jane Doe" not in result.redacted_text

    # ── Address detection ────────────────────────────────────────────────

    def test_redacts_street_address(self):
        result = self.redactor.redact("I live at 123 Main Street, Springfield IL 62704")
        assert "123 Main Street" not in result.redacted_text
        assert "[ADDRESS_" in result.redacted_text

    # ── Date of birth ────────────────────────────────────────────────────

    def test_redacts_dob(self):
        result = self.redactor.redact("DOB: 01/15/1990")
        assert "01/15/1990" not in result.redacted_text
        assert "[DOB_" in result.redacted_text

    def test_redacts_dob_with_label(self):
        result = self.redactor.redact("date of birth: 1990-01-15")
        assert "1990-01-15" not in result.redacted_text

    # ── Insurance / policy numbers ───────────────────────────────────────

    def test_redacts_policy_number(self):
        result = self.redactor.redact("Policy number: ABC123456789")
        assert "ABC123456789" not in result.redacted_text
        assert "[POLICY_" in result.redacted_text

    def test_redacts_member_id(self):
        result = self.redactor.redact("Member ID: XYZ-987654")
        assert "XYZ-987654" not in result.redacted_text

    # ── Stable token mapping ─────────────────────────────────────────────

    def test_same_value_gets_same_token(self):
        result = self.redactor.redact(
            "Email john@test.com and again john@test.com"
        )
        # Should produce only one mapping entry
        unique_originals = set(m.original for m in result.mappings)
        assert len(unique_originals) == 1

    def test_mapping_allows_restore(self):
        result = self.redactor.redact("Contact john@test.com")
        restored = self.redactor.restore(result.redacted_text)
        assert "john@test.com" in restored

    def test_restore_with_multiple_types(self):
        text = "Name: John Smith, email: john@test.com, phone: 555-123-4567"
        result = self.redactor.redact(text)
        restored = self.redactor.restore(result.redacted_text)
        assert "John Smith" in restored or "john@test.com" in restored

    # ── Edge cases ───────────────────────────────────────────────────────

    def test_empty_string(self):
        result = self.redactor.redact("")
        assert result.redacted_text == ""
        assert len(result.mappings) == 0

    def test_no_pii(self):
        text = "I feel anxious about my upcoming appointment"
        result = self.redactor.redact(text)
        assert result.redacted_text == text
        assert len(result.mappings) == 0

    def test_preserves_clinical_content(self):
        text = "Patient reports feeling hopeless and having trouble sleeping for 3 weeks"
        result = self.redactor.redact(text)
        assert "hopeless" in result.redacted_text
        assert "trouble sleeping" in result.redacted_text
        assert "3 weeks" in result.redacted_text


class TestRedactionResult:
    """RedactionResult data class behavior."""

    def test_result_has_required_fields(self):
        result = RedactionResult(redacted_text="hello", mappings=[])
        assert result.redacted_text == "hello"
        assert result.mappings == []


class TestFieldAllowlist:
    """Field-level allowlist enforcement."""

    def setup_method(self):
        self.redactor = Redactor()

    def test_filter_fields_keeps_allowed(self):
        data = {"age": 35, "name": "John Smith", "symptoms": "anxiety"}
        allowed = {"age", "symptoms"}
        filtered = self.redactor.filter_fields(data, allowed)
        assert filtered == {"age": 35, "symptoms": "anxiety"}

    def test_filter_fields_removes_disallowed(self):
        data = {"name": "John", "email": "j@t.com", "concern": "stress"}
        allowed = {"concern"}
        filtered = self.redactor.filter_fields(data, allowed)
        assert "name" not in filtered
        assert "email" not in filtered
        assert filtered == {"concern": "stress"}
