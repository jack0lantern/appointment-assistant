# Deep Link Contract: `GET /api/onboard/:slug`

This document defines the API contract for onboarding deep links in the Rails backend.

## Purpose

Allow authenticated users arriving from referral links (for example, `/onboard/dr-smith`) to start or resume a user-owned onboarding conversation with therapist context pre-assigned.

## Endpoint

- **Method:** `GET`
- **Path:** `/api/onboard/:slug`
- **Auth:** Required (JWT bearer token)

## Request

- **Path param:** `slug` (therapist slug; case-insensitive match policy is implementation-defined but must be deterministic)
- **Headers:** `Authorization: Bearer <jwt>`

## Behavior

1. Validate JWT and resolve authenticated user.
2. Resolve `slug` to therapist record.
3. If therapist slug is invalid, return `404`.
4. Create or resume a conversation owned by the authenticated user.
5. Set onboarding state `assigned_therapist_id` to resolved therapist ID.
6. Return conversation bootstrap payload for frontend chat initialization.

## Ownership Rule

- The resulting conversation must always belong to the authenticated user.
- A user must never receive another user's conversation, even if they share the same therapist slug.

## Success Response (200)

```json
{
  "conversation_id": "string",
  "context_type": "onboarding",
  "assigned_therapist": {
    "display_name": "Dr. Example",
    "slug": "dr-example"
  },
  "onboarding_progress": {
    "assigned_therapist_id": "internal-id",
    "is_new_user": true
  },
  "welcome_message": "string"
}
```

Notes:
- `assigned_therapist_id` is internal server state. It should not be exposed to the LLM as a raw database identifier.
- Client-facing therapist references should use display-safe values.

## Error Responses

- `401 Unauthorized`: missing/invalid token
- `404 Not Found`: no therapist for slug
- `422 Unprocessable Entity`: malformed request (if validation fails)

## Security Constraints

1. JWT auth required on every call.
2. Conversation ownership enforced server-side.
3. No raw PHI/PII leakage in response payload.
4. Audit logs must mask sensitive values.

## Phase Mapping

- **Phase 0:** Contract defined.
- **Phase 2:** Endpoint implemented and covered by request specs.

