"""OCR service for document text extraction.

Extracts text and structured fields from uploaded documents (insurance cards,
IDs, intake forms). All extracted data goes through the redaction layer before
any LLM usage.

This is a pluggable stub — swap the OCR backend without changing the interface.
"""

from __future__ import annotations

import logging
import re
from typing import Any

from app.schemas.agent import ExtractedField
from app.utils.redaction import Redactor

logger = logging.getLogger(__name__)


class OCRService:
    """Document text extraction with privacy-preserving output."""

    def __init__(self, redactor: Redactor | None = None) -> None:
        self.redactor = redactor or Redactor()

    async def extract_text(self, file_bytes: bytes, filename: str) -> str:
        """Extract raw text from an image/PDF file.

        TODO: Integrate a real OCR backend (Tesseract, Google Vision, AWS Textract).
        For now, returns a stub response for demo/testing.
        """
        # Stub: in production, this would call an OCR API
        logger.info("OCR extraction requested for file: %s (%d bytes)", filename, len(file_bytes))
        return f"[OCR stub] Document '{filename}' received ({len(file_bytes)} bytes). OCR extraction pending backend integration."

    async def extract_fields(
        self,
        raw_text: str,
        document_type: str | None = None,
    ) -> list[ExtractedField]:
        """Parse structured fields from OCR text.

        Uses pattern matching to identify common fields.
        In production, an LLM could enhance extraction (with redacted input).
        """
        fields: list[ExtractedField] = []

        # Name patterns
        name_match = re.search(r"(?:name|patient|insured)\s*:?\s*([A-Z][a-z]+\s+[A-Z][a-z]+)", raw_text, re.IGNORECASE)
        if name_match:
            fields.append(ExtractedField(field_name="name", value=name_match.group(1), confidence=0.85))

        # DOB patterns
        dob_match = re.search(r"(?:dob|date\s*of\s*birth|birth\s*date)\s*:?\s*(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4})", raw_text, re.IGNORECASE)
        if dob_match:
            fields.append(ExtractedField(field_name="date_of_birth", value=dob_match.group(1), confidence=0.90))

        # Policy number
        policy_match = re.search(r"(?:policy|member|id)\s*(?:number|#|no\.?)?\s*:?\s*([A-Z0-9\-]{6,20})", raw_text, re.IGNORECASE)
        if policy_match:
            fields.append(ExtractedField(field_name="policy_number", value=policy_match.group(1), confidence=0.80))

        # Group number
        group_match = re.search(r"(?:group)\s*(?:number|#|no\.?)?\s*:?\s*([A-Z0-9\-]{4,15})", raw_text, re.IGNORECASE)
        if group_match:
            fields.append(ExtractedField(field_name="group_number", value=group_match.group(1), confidence=0.75))

        return fields

    def redact_for_llm(self, raw_text: str) -> str:
        """Redact OCR output before sending to LLM.

        Returns only the redacted version. Raw text stays server-side.
        """
        result = self.redactor.redact(raw_text)
        return result.redacted_text

    async def process_document(
        self,
        file_bytes: bytes,
        filename: str,
        document_type: str | None = None,
    ) -> dict[str, Any]:
        """Full pipeline: extract → parse fields → redact.

        Returns:
            {
                "raw_text": str (stored server-side only),
                "redacted_preview": str (safe for LLM),
                "fields": list[ExtractedField],
            }
        """
        raw_text = await self.extract_text(file_bytes, filename)
        fields = await self.extract_fields(raw_text, document_type)
        redacted_preview = self.redact_for_llm(raw_text)

        return {
            "raw_text": raw_text,
            "redacted_preview": redacted_preview,
            "fields": fields,
        }
