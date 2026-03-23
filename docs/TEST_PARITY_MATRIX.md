# Parity Matrix: Tests, Routes, and Contracts

This file documents the parity baseline from the Python/FastAPI to Rails migration (completed).

- **Target:** `backend_rails/` (Rails)
- **Historical reference:** The Python backend has been removed; this matrix documents what was migrated.

---

## 1) Test File Mapping (pytest -> RSpec)

| Python Test File | Tests | Rails Spec File | Status | Notes |
|---|---:|---|---|---|
| `test_redaction.py` | 23 | `spec/services/redaction_service_spec.rb` | Pending | Redaction correctness and stable token mapping |
| `test_safety_detection.py` | 28 | `spec/utils/safety_patterns_spec.rb` | Pending | Crisis and clinical risk pattern behavior |
| `test_agent_eval.py` | 38 | `spec/services/agent_service_eval_spec.rb` | Pending | End-to-end agent behaviors + tool-calling safety |
| `test_agent_routes.py` | 4 | `spec/requests/agent_chat_spec.rb` | Pending | HTTP contract for `POST /api/agent/chat` |
| `test_agent_service.py` | 19 | `spec/services/agent_service_spec.rb` | Pending | Intent routing, safety checks, suggestions |
| `test_ai_output_parsing.py` | 6 | `spec/schemas/treatment_plan_content_spec.rb` | Pending | AI output structure validation |
| `test_draft_plans_api.py` | 5 | `spec/requests/draft_plans_spec.rb` | Pending | Draft plans endpoints and gating |
| `test_emotional_support.py` | 10 | `spec/services/emotional_support_spec.rb` | Pending | Emotional support utility outputs |
| `test_evaluation_enhancements.py` | 12 | `spec/services/evaluation_service_spec.rb` | Pending | Evaluation service + streaming/cancel semantics |
| `test_ocr_service.py` | 8 | `spec/services/ocr_service_spec.rb` | Pending | OCR extraction and redaction boundary |
| `test_plan_validation.py` | 4 | `spec/services/plan_validation_spec.rb` | Pending | Structural and readability guardrails |
| `test_readability.py` | 5 | `spec/utils/readability_spec.rb` | Pending | Grade-level calculations |
| `test_scheduling_delegation.py` | 11 | `spec/services/scheduling_delegation_spec.rb` | Pending | Therapist delegation + auth boundaries |
| `test_scheduling_service.py` | 6 | `spec/services/scheduling_service_spec.rb` | Pending | Slot generation and booking constraints |

### Test Summary

| Metric | Count |
|---|---:|
| Python test files | 14 |
| Python test functions | 179 |
| Rails spec files mapped | 14 |
| Ported | 0 |
| Pending | 14 |

---

## 2) API Route Parity Matrix

Status legend:
- **Implemented:** Route exists in Rails with matching intent
- **Planned (Phase N):** Route is intentionally deferred to listed phase
- **Needs Contract Review:** Route exists but response envelope must be confirmed before signoff

| Python Route | Python Source | Rails Target | Status | Notes |
|---|---|---|---|---|
| `GET /health` | `app.main` | `GET /health` | Implemented | Returns `{ "status": "ok" }` |
| `POST /api/auth/login` | `routes/auth.py` | `POST /api/auth/login` | Implemented | Must keep token + user envelope parity |
| `GET /api/auth/me` | `routes/auth.py` | `GET /api/auth/me` | Planned (Phase 1) | Auth middleware and user serializer parity |
| `POST /api/agent/chat` | `routes/agent.py` | `POST /api/agent/chat` | Planned (Phase 1) | Core chat endpoint parity requirement |
| `GET /api/agent/scheduling/availability` | `routes/agent_scheduling.py` | same path | Planned (Phase 1) | Tool and route-level parity |
| `POST /api/agent/scheduling/book` | `routes/agent_scheduling.py` | same path | Planned (Phase 1) | Client/therapist auth boundary parity |
| `POST /api/agent/scheduling/cancel` | `routes/agent_scheduling.py` | same path | Planned (Phase 1) | Ownership checks must match Python behavior |
| `GET /api/onboard/:slug` | PRD + plan contract | `GET /api/onboard/:slug` | Planned (Phase 2) | See `docs/DEEP_LINK_CONTRACT.md` |
| `POST /api/agent/documents/upload` | Plan contract | same path | Planned (Phase 3) | See retention/security policy doc |
| `GET /api/clients` and related CRUD | `routes/clients.py` | same logical endpoints | Planned (Phase 1+) | Preserve response shape where possible |
| `GET /api/my/*` client portal routes | `routes/client_routes.py` | same logical endpoints | Planned (Phase 1+) | Requires auth + client ownership parity |
| `POST /api/evaluation/*` | `routes/evaluation.py` | same logical endpoints | Planned (Phase 1+) | Streaming/cancel semantics require adaptation |

---

## 3) Response Contract / Serializer Parity

Contract baseline sources:
- Blueprinter serializers in `backend_rails/app/blueprints/`
- API response contracts in `backend_rails/app/controllers/`

| Contract Area | Python Schema Source | Rails Blueprint / Contract | Status |
|---|---|---|---|
| Auth user/login | `schemas/auth.py` | `UserBlueprint` + auth controller responses | In progress |
| Therapist profile/public card | therapist data used by onboarding/search flows | `TherapistBlueprint` | Implemented baseline |
| Client | `schemas/client.py` | `ClientBlueprint` | Implemented baseline |
| Session/transcript | `schemas/session.py` | `SessionBlueprint`, `TranscriptBlueprint` | Implemented baseline |
| Treatment plan/version | `schemas/treatment_plan.py` | `TreatmentPlanBlueprint`, `TreatmentPlanVersionBlueprint` | Implemented baseline |
| Safety flags | `schemas/safety.py` | `SafetyFlagBlueprint` | Implemented baseline |
| Agent chat envelopes | `schemas/agent.py` | `AgentBlueprint` + request specs | Planned (Phase 1) |
| Conversation/message | conversation schemas in agent flow | `ConversationBlueprint`, `ConversationMessageBlueprint` | Implemented baseline |
| Evaluation payloads | `schemas/evaluation.py` | Rails serializer/contract TBD | Planned (Phase 1+) |
| Homework payloads | `schemas/homework.py` | Rails serializer/contract TBD | Planned (Phase 1+) |

---

## 4) Migration Notes (High-Risk Differences)

1. **Async patterns**: Python async route/service tests map to synchronous-by-default RSpec; behavior parity matters more than implementation style.
2. **Streaming + cancellation**: Evaluation stream/cancel behavior needs Rails-native implementation (SSE/ActionCable/background jobs).
3. **Dependency override patterns**: FastAPI dependency overrides become Rails test setup + service stubs.
4. **Readability scoring library**: Python `textstat` requires Ruby-equivalent implementation/validation.
5. **Pydantic validation semantics**: Must be replicated in Rails contracts for strict structural guarantees.
6. **Anthropic client mocking**: Ruby SDK stubs must preserve tool-call loop and safety behavior tests.

