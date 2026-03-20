"""Tests for the OCR service."""

import pytest

from app.services.ocr_service import OCRService
from app.utils.redaction import Redactor


class TestOCRService:
    """OCR extraction and field parsing."""

    @pytest.fixture
    def service(self):
        return OCRService()

    @pytest.mark.asyncio
    async def test_extract_text_returns_string(self, service):
        result = await service.extract_text(b"fake-image-data", "card.jpg")
        assert isinstance(result, str)
        assert len(result) > 0

    @pytest.mark.asyncio
    async def test_extract_fields_finds_name(self, service):
        text = "Patient Name: John Smith\nDOB: 01/15/1990\nPolicy Number: ABC123456"
        fields = await service.extract_fields(text)
        names = [f for f in fields if f.field_name == "name"]
        assert len(names) == 1
        assert "John Smith" in names[0].value

    @pytest.mark.asyncio
    async def test_extract_fields_finds_dob(self, service):
        text = "Name: Jane Doe\nDate of Birth: 03/22/1985"
        fields = await service.extract_fields(text)
        dob = [f for f in fields if f.field_name == "date_of_birth"]
        assert len(dob) == 1
        assert "03/22/1985" in dob[0].value

    @pytest.mark.asyncio
    async def test_extract_fields_finds_policy(self, service):
        text = "Member ID: XYZ-987654\nGroup: GRP-001"
        fields = await service.extract_fields(text)
        policy = [f for f in fields if f.field_name == "policy_number"]
        assert len(policy) == 1

    def test_redact_for_llm_masks_pii(self, service):
        text = "Patient: John Smith, email: john@test.com, SSN: 123-45-6789"
        redacted = service.redact_for_llm(text)
        assert "John Smith" not in redacted
        assert "john@test.com" not in redacted
        assert "123-45-6789" not in redacted

    @pytest.mark.asyncio
    async def test_process_document_returns_all_fields(self, service):
        result = await service.process_document(b"data", "test.jpg", "insurance_card")
        assert "raw_text" in result
        assert "redacted_preview" in result
        assert "fields" in result


class TestOCRRedactionIntegration:
    """OCR output goes through redaction before LLM use."""

    def test_shared_redactor(self):
        redactor = Redactor()
        service = OCRService(redactor=redactor)
        assert service.redactor is redactor

    def test_redacted_output_has_no_raw_pii(self):
        service = OCRService()
        text = "Name: Jane Doe\nPhone: (555) 123-4567\nPolicy: POL-12345678"
        redacted = service.redact_for_llm(text)
        assert "(555) 123-4567" not in redacted
