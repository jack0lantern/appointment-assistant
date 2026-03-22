# Document Retention Policy (Phase 0 Baseline)

This policy defines how uploaded onboarding documents and OCR artifacts are retained and purged in the Rails backend migration.

## Scope

Applies to:
- Raw uploaded files (insurance cards, intake docs, images/PDFs)
- Raw OCR output text
- Extracted structured fields before redaction

Does not apply to:
- Redacted summaries written to conversation history
- Standard chat messages not containing raw document payloads

## Security and Storage Rules

1. Raw uploads and raw OCR text are **server-side only**.
2. Raw uploads and raw OCR text are **never** sent to the LLM.
3. Conversation history stores only redacted summaries derived from document processing.
4. Logs must not include raw OCR text, policy/member numbers, DOB, or full addresses.

## Default Retention Windows

- **Raw uploaded files:** 7 days
- **Raw OCR text/artifacts:** 7 days
- **Redacted document summary in conversation:** retained as part of normal chat record retention

Rationale:
- 7 days provides enough time for verification, retries, and support debugging.
- Short retention window minimizes PHI exposure if storage is compromised.

## Purge Behavior

Background cleanup job requirements:
1. Run at least daily.
2. Delete raw uploaded files and OCR artifacts older than 7 days.
3. Keep deletion idempotent (safe to run repeatedly).
4. Emit audit logs with masked metadata only (document reference, timestamps, status).

## Operational Guardrails

- If processing fails, retry within retention window only.
- Manual support access to raw artifacts is limited to authorized roles.
- Export endpoints must never expose raw OCR text without explicit privileged access checks.

## Phase Mapping

- **Phase 0:** Policy defined and committed.
- **Phase 3:** Upload/OCR pipeline must enforce this policy with an actual cleanup job.

