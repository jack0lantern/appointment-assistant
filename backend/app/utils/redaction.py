"""PII/PHI redaction layer for LLM-bound data.

Detects and replaces direct identifiers (names, emails, phones, SSNs,
addresses, DOBs, policy/member IDs) with stable tokens before any data
is sent to an external LLM. A server-side mapping allows restoring
original values without ever exposing the mapping to the LLM.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any


@dataclass
class RedactionMapping:
    """Maps a token back to its original value."""

    token: str
    original: str
    pii_type: str


@dataclass
class RedactionResult:
    """Outcome of a redaction pass."""

    redacted_text: str
    mappings: list[RedactionMapping] = field(default_factory=list)


# ── Pattern definitions ──────────────────────────────────────────────────────
# Order matters: more specific patterns first to avoid partial matches.

_EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}")

_SSN_RE = re.compile(
    r"\b(\d{3}-\d{2}-\d{4})\b"          # 123-45-6789
    r"|(?<=SSN\s)(\d{9})\b"              # SSN 123456789
    r"|(?<=ssn\s)(\d{9})\b"
)

_PHONE_RE = re.compile(
    r"\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}"
)

_DOB_RE = re.compile(
    r"(?:(?:DOB|dob|date\s+of\s+birth|Date\s+of\s+Birth)\s*:?\s*)"
    r"(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}|\d{4}[/\-]\d{1,2}[/\-]\d{1,2})"
)

_POLICY_RE = re.compile(
    r"(?:(?:policy|member|insurance|group)\s*(?:number|id|#|no\.?)\s*:?\s*)"
    r"([A-Za-z0-9\-]{6,20})",
    re.IGNORECASE,
)

_NAME_PREFIX_RE = re.compile(
    r"(?:patient\s*(?:name)?|name|my\s+name\s+is|client|insured)\s*:\s*",
    re.IGNORECASE,
)
# Name capture is case-sensitive: requires Title Case words after a prefix + colon
_NAME_RE = re.compile(
    r"(?:(?:[Pp]atient\s*(?:[Nn]ame)?|[Nn]ame|[Mm]y\s+[Nn]ame\s+[Ii]s|[Cc]lient|[Ii]nsured)\s*:?\s*)"
    r"([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)",
)

_ADDRESS_RE = re.compile(
    r"\b(\d{1,6}\s+[A-Z][a-zA-Z]*(?:\s+[A-Z][a-zA-Z]*)*"
    r"\s+(?:Street|St|Avenue|Ave|Boulevard|Blvd|Drive|Dr|Road|Rd|Lane|Ln|Way|Court|Ct|Place|Pl)"
    r"(?:\s*,\s*[A-Za-z\s]+(?:\s+[A-Z]{2}\s+\d{5})?)?)",
    re.IGNORECASE,
)

# Ordered list of (pattern, pii_type, group_index_or_none)
# group_index=None means use group(0) (full match)
_PATTERNS: list[tuple[re.Pattern, str, int | None]] = [
    (_SSN_RE, "SSN", None),
    (_EMAIL_RE, "EMAIL", None),
    (_DOB_RE, "DOB", 1),
    (_POLICY_RE, "POLICY", 1),
    (_NAME_RE, "NAME", 1),
    (_ADDRESS_RE, "ADDRESS", None),
    (_PHONE_RE, "PHONE", None),
]


class Redactor:
    """Stateful redactor that maintains a token ↔ original mapping.

    One Redactor instance should be used per conversation/session so that
    the same PII value always maps to the same token within that scope.
    """

    def __init__(self) -> None:
        self._original_to_token: dict[str, str] = {}
        self._token_to_original: dict[str, str] = {}
        self._counters: dict[str, int] = {}

    def _get_or_create_token(self, original: str, pii_type: str) -> str:
        """Return stable token for a given original value."""
        if original in self._original_to_token:
            return self._original_to_token[original]
        count = self._counters.get(pii_type, 0) + 1
        self._counters[pii_type] = count
        token = f"[{pii_type}_{count}]"
        self._original_to_token[original] = token
        self._token_to_original[token] = original
        return token

    def redact(self, text: str) -> RedactionResult:
        """Scan text for PII/PHI and replace with stable tokens."""
        if not text:
            return RedactionResult(redacted_text="", mappings=[])

        mappings: list[RedactionMapping] = []
        result = text

        for pattern, pii_type, group_idx in _PATTERNS:
            # Find all matches, replace from right to left to preserve indices
            matches = list(pattern.finditer(result))
            for match in reversed(matches):
                if group_idx is not None:
                    original = match.group(group_idx)
                    if original is None:
                        continue
                    # Find the span of the captured group within the full match
                    start = match.start(group_idx)
                    end = match.end(group_idx)
                else:
                    original = match.group(0)
                    start = match.start()
                    end = match.end()

                token = self._get_or_create_token(original.strip(), pii_type)
                result = result[:start] + token + result[end:]
                mappings.append(
                    RedactionMapping(
                        token=token, original=original.strip(), pii_type=pii_type
                    )
                )

        # Deduplicate mappings (same original may appear multiple times)
        seen = set()
        unique_mappings = []
        for m in mappings:
            if m.original not in seen:
                seen.add(m.original)
                unique_mappings.append(m)

        return RedactionResult(redacted_text=result, mappings=unique_mappings)

    def restore(self, redacted_text: str) -> str:
        """Replace tokens back with original values (server-side only)."""
        result = redacted_text
        for token, original in self._token_to_original.items():
            result = result.replace(token, original)
        return result

    def filter_fields(
        self, data: dict[str, Any], allowed_fields: set[str]
    ) -> dict[str, Any]:
        """Return only fields in the allowlist. Everything else is dropped."""
        return {k: v for k, v in data.items() if k in allowed_fields}
