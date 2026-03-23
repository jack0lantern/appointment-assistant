# Orchestrated Multi-Agent Implementation Plan: AI Therapy Onboarding Assistant

## Overview

This plan defines how to build the AI-powered onboarding assistant described in the [PRD](AI%20Therapy%20Assistant%20PRD%20Draft.md), migrating the backend from Python/FastAPI to Ruby on Rails while preserving all existing behavior, security patterns, and test coverage.

The backend has been fully migrated to Rails. The `credal-agent` branch can be used as a reference for Credal-specific onboarding behavior. The frontend (React/Vite/TypeScript) is unchanged.

---

## Architectural Decisions (Resolved)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | TypeScript/LangGraph vs Python extension | Extend existing pipeline (now Rails) | PRD graph is conceptual, not a stack requirement |
| 2 | State model | Nested `OnboardingProgress` as JSONB on `conversations` | Keeps onboarding fields separate from general chat state |
| 3 | Deep link route | Backend-controlled `GET /api/onboard/:slug` with JWT auth | Frontend preserves slug through login/signup, then backend creates or resumes a user-scoped conversation with `assigned_therapist_id` |
| 4 | Therapist search | Tool-only (no REST endpoint) | LLM calls `search_therapists` tool, queries DB via service layer |
| 5 | Document upload | Separate `POST /api/agent/documents/upload` + async processing | Decoupled from chat, supports progress polling and keeps OCR/PHI handling server-side |
| 6 | Trauma dumping | Out of scope for initial Rails migration | Explicit PRD deviation for this version; revisit after core onboarding flow is stable |
| 7 | Human escalation | Stub with logging interface | Demo-grade; clear interface for future swap to webhook/email |
| 8 | Language/framework | Ruby on Rails (API mode) | Per Credal PRD requirement |
| 9 | Serialization | Blueprinter | Lightweight, explicit JSON contracts, good fit for API-only Rails |
| 10 | Anthropic integration | `anthropic-rb` | Lowest-friction path to parity with current Claude usage |
| 11 | Auth | `jwt` gem + custom middleware | Matches existing API-style auth without adding full Devise complexity |
| 12 | Migration strategy | Full migration to Rails, prefer same routes and response shapes | Minimizes frontend churn and preserves API contracts |

---

## Tech Stack (Revised)

| Layer | Choice |
|-------|--------|
| **Backend** | Ruby on Rails 7+ (API mode) |
| **ORM** | ActiveRecord + Rails migrations |
| **Database** | PostgreSQL (JSONB for onboarding progress, plan content) |
| **Validation/Serialization** | Strong Parameters + Blueprinter |
| **AI Integration** | Anthropic Ruby SDK (`anthropic-rb`) |
| **Auth** | JWT (`jwt` gem) + custom middleware |
| **Testing** | RSpec + FactoryBot |
| **Frontend** | React + Vite + TypeScript (unchanged) |
| **Styling** | Tailwind CSS + shadcn/ui (unchanged) |

---

## High-Level Summary

1. **The PRD describes a conversational onboarding assistant** that routes new vs. returning users through intake, document upload, therapist search, risk evaluation, scheduling, and human escalation.

2. **The existing Python chat agent pipeline** (`input_safety → classify_intent → redact_pii → build_context → call_llm + tools → response_safety_check → append_actions`) is the behavioral specification. Rails rewrite preserves this flow exactly.

3. **PRD nodes map to service objects:**
   - `Intake_Agent` → `onboarding` context type + enriched system prompt
   - `Risk_Evaluator` → `InputSafetyService` + background risk accumulator
   - `Therapist_Search` → new `search_therapists` tool + `TherapistSearchService`
   - `Document_Processor` → `DocumentProcessorService` + `upload_document` tool
   - `Scheduling_Tool` → existing `book_appointment` / `get_available_slots` tools
   - `Human_Escalation` → `EscalationService` (stub with logging)

4. **State extension:** `OnboardingProgress` stored as JSONB on `conversations` table: `is_new_user`, `has_completed_intake`, `assigned_therapist_id`, `selected_therapist_id`, `risk_level`, `docs_verified`, `appointment_id`.

5. **Zero-ID UX:** LLM sees therapist bios with display labels, never raw UUIDs. Backend maps labels → real IDs server-side.

6. **Parity baseline:** The migration matrix (`docs/TEST_PARITY_MATRIX.md`) documents the original Python test/route mapping. New onboarding specs are added as needed.

7. **Migration target:** Rails is the sole backend. Same HTTP methods, paths, auth rules, and response envelopes as the original design unless a documented contract change is approved.

---

## Migration & Security Constraints

- **Deep-link auth/bootstrap:** `GET /api/onboard/:slug` requires JWT auth. The frontend preserves the slug through login/signup, then calls the endpoint after auth so routing can rely on `auth_context.user_id` from the first server-owned turn.
- **Conversation ownership:** Deep-link onboarding always creates or resumes a conversation owned by the authenticated user. Protected actions (`upload_document`, scheduling tools, future escalation actions) must validate both JWT auth and conversation ownership.
- **Document lifecycle:** Uploaded files are stored in protected server-side storage via Rails-managed attachments. OCR runs asynchronously, raw uploads and raw OCR text never enter chat history, and only redacted summaries are persisted in conversation messages.
- **PHI retention:** Raw uploads/OCR artifacts are retained only as long as needed for verification/debugging, with a default purge window defined in Phase 0 and enforced by background cleanup.
- **Cutover contract:** Rails is the only backend. Migration is complete; parity matrix and rollback steps are documented.

---

## Explicit Scope Boundaries

- **Out of scope now:** PRD trauma-dumping threshold/interruption behavior. The initial Rails migration focuses on onboarding, provider search, document handling, scheduling, and escalation guardrails.
- **In scope now:** Crisis short-circuiting, PII/PHI redaction, scoped scheduling actions, provider matching, document verification, and paused-conversation handling.

---

## Agent Roles & Responsibilities

### Orchestrator Agent
- Owns shared contracts (state fields, tool interfaces, serializers)
- Sequences phases and coordinates parallel work
- Invokes critic agents at checkpoints
- Resolves conflicts when agents touch shared modules

### Implementation Agents

| Agent | Scope | Key Modules |
|-------|-------|-------------|
| **Rails Migration Agent** | Port all existing Python services/models/routes to Rails | All `app/models/`, `app/services/`, `app/controllers/` |
| **Onboarding & State Agent** | Onboarding routing, state management, deep link support | `AgentService`, `OnboardingProgress`, `ConversationsController` |
| **Provider Search & Matching Agent** | `search_therapists` tool, fuzzy matching, zero-ID UX, slug resolution | `TherapistSearchService`, `AgentTools` |
| **Document Processing Agent** | Upload endpoint, OCR → redaction pipeline, `docs_verified` state | `DocumentProcessorService`, `DocumentsController` |
| **Edge Cases Agent** | Phantom booking (conflict → retry), human escalation stub | `SchedulingService`, `EscalationService` |
| **Frontend Chat UX Agent** | Therapist cards, document upload widget, onboarding progress, deep link page | `ChatWidget.tsx`, `useChat.ts`, new components |

### QA Agent
- Writes **failing RSpec tests first** (RED) for each phase before any production code
- Runs `rspec` after each GREEN step
- Owns test file creation and placement
- New spec files listed per phase below

### Critic Agents

| Critic | Trigger | Checks |
|--------|---------|--------|
| **Auditor** | End of each phase | Every PRD node/edge represented in code + tests. Coverage matrix: PRD requirement → spec file:example. |
| **Security** | End of Phases 1, 3, 4 | PII/PHI never reaches LLM unredacted. Auth enforced on all tools. No raw UUIDs in chat. Scoped scheduling actions. Masked audit logs. |
| **Implementation** | End of each phase | Rails idioms (service objects, concerns, proper ActiveRecord). No over-engineering. Consistency across services. |

---

## Phased Plan

### Phase 0: Rails Project Setup & Shared Contracts
**Sequential — must complete before all other phases.**

**Goals:**
- Initialize Rails API project with PostgreSQL
- Set up RSpec, FactoryBot, database config, CI
- Parity matrix documents original Python→Rails migration (see `docs/TEST_PARITY_MATRIX.md`)
- Define ActiveRecord models mirroring existing SQLAlchemy models:
  - `User`, `Client`, `Therapist`, `Session`, `Conversation`, `ConversationMessage`
  - `TreatmentPlan`, `TreatmentPlanVersion`, `SafetyFlag`, `HomeworkItem`, `EvaluationRun`
  - `Transcript`, `SessionSummary`, `RecordingConsent`
- Add `onboarding_progress` JSONB column to `conversations` migration
- Add conversation status support (`active`, `paused`) to preserve safety gating semantics
- Add `slug` column to `therapists` migration
- Define Blueprinter serializers matching existing Pydantic schemas / current JSON contracts
- Define the authenticated deep-link bootstrap contract (`/api/onboard/:slug`) and document retention policy
- Set up Anthropic Ruby SDK integration
- `GET /health` responds

**Tests (RSpec, RED first):**
- `spec/models/` — model validations, associations, factory definitions
- `spec/requests/health_spec.rb` — health endpoint returns 200

**Critic:** Implementation Critic reviews Rails project structure and model design.

---

### Phase 1: Chat Agent Pipeline in Rails
**Depends on:** Phase 0

**Goals:**
- Port the full chat agent pipeline:
  - `InputSafetyService` — crisis pattern detection (port regex from Python `safety_patterns.py`)
  - `IntentClassifier` — keyword-based routing (port from Python `agent_service.py`)
  - `RedactionService` — PII/PHI masking (port from Python `redaction.py`)
  - `ContextBuilder` — system prompt construction per context type
  - `LlmService` — Claude API with tool-calling loop (max 5 rounds)
  - `ResponseSafetyService` — output filtering (diagnosis, medication, medical advice)
  - `AgentService` — orchestrates the full pipeline
- Port all 8 existing tools to `AgentTools` module:
  - `get_current_datetime`, `get_available_slots`, `book_appointment`, `cancel_appointment`
  - `get_grounding_exercise`, `get_psychoeducation`, `get_what_to_expect`, `get_validation_message`
- Port `SchedulingService`, `EmotionalSupportService`, `OcrService`
- Auth middleware: JWT validation, `ToolAuthContext` equivalent
- Preserve or intentionally document any route/response differences from Python; default is same routes and response envelopes
- Add minimum safety state handling needed by downstream onboarding flows:
  - persist `risk_level` on the conversation / onboarding state each turn
  - short-circuit crisis responses without LLM calls
  - block normal assistant replies for `paused` conversations
- `POST /api/agent/chat` endpoint
- `GET /api/agent/scheduling/availability`, `POST /api/agent/scheduling/book`, `POST /api/agent/scheduling/cancel`

**Tests (RSpec, RED first — ported from existing pytest):**

| Spec File | Ported From | Est. Tests |
|-----------|-------------|------------|
| `spec/services/redaction_service_spec.rb` | `test_redaction.py` | ~23 |
| `spec/services/agent_service_spec.rb` | `test_agent_service.py` | ~15 |
| `spec/services/safety_detection_spec.rb` | `test_safety_detection.py` | ~60 |
| `spec/services/scheduling_service_spec.rb` | `test_scheduling_service.py` + `test_scheduling_delegation.py` | ~17 |
| `spec/services/emotional_support_spec.rb` | `test_emotional_support.py` | ~10 |
| `spec/services/ocr_service_spec.rb` | `test_ocr_service.py` | ~8 |
| `spec/requests/agent_chat_spec.rb` | `test_agent_routes.py` | ~4 |
| `spec/requests/agent_scheduling_spec.rb` | `test_agent_routes.py` | ~6 |
| `spec/integration/agent_eval_spec.rb` | `test_agent_eval.py` | ~34 |
| `spec/services/ai_output_parsing_spec.rb` | `test_ai_output_parsing.py` | ~8 |
| `spec/services/plan_validation_spec.rb` | `test_plan_validation.py` | ~12 |
| `spec/services/readability_spec.rb` | `test_readability.py` | ~6 |
| `spec/services/evaluation_enhancements_spec.rb` | `test_evaluation_enhancements.py` | ~10 |
| `spec/requests/draft_plans_api_spec.rb` | `test_draft_plans_api.py` | ~8 |

**Target:** Behavioral parity with the full Python backend (~221 existing pytest examples across 15 files), with every pytest file explicitly mapped to a Rails spec before Phase 6 signoff.

**Critic checkpoint:**
- Implementation Critic: Rails idioms, service object patterns, proper use of ActiveRecord
- Security Critic: PII handling matches Python implementation exactly

---

### Phase 2: Onboarding Routing & State + Provider Search
**Depends on:** Phase 1. **Two parallel tracks within phase.**

#### Track A — Onboarding Routing & State

**Goals:**
- New vs. returning user detection (query `clients` table by `auth_context.user_id`)
- `OnboardingProgress` value object (backed by JSONB): `is_new_user`, `has_completed_intake`, `assigned_therapist_id`, `selected_therapist_id`, `risk_level`, `docs_verified`, `appointment_id`
- Routing logic:
  - New user → intake flow (enriched onboarding system prompt)
  - Returning, no therapist → therapist search
  - Returning, has therapist → scheduling
- Persist `OnboardingProgress` across conversation turns
- Persist and honor `risk_level` / `paused` state during onboarding so later phases do not have to retrofit the core guardrail
- Onboarding-specific system prompt additions

**Tests (RED first):**
- `spec/services/onboarding_routing_spec.rb`:
  - `it routes new users to intake`
  - `it routes returning users without therapist to search`
  - `it routes returning users with therapist to scheduling`
  - `it persists onboarding progress across turns`
  - `it enriches system prompt for intake flow`

#### Track B — Provider Search (Tool-Only) + Deep Link

**Goals:**
- New `search_therapists` tool added to `AgentTools`
- `TherapistSearchService`:
  - Fuzzy matching by name (`pg_trgm` or `ILIKE`)
  - Filter by specialty, gender, insurance
  - Returns `TherapistSearchResult` with display labels and public bios
- Zero-ID UX: display labels (`"Dr. A"`, `"Dr. B"`) mapped to real IDs server-side
- On user confirmation, save `selected_therapist_id` in `OnboardingProgress`
- Deep link: `GET /api/onboard/:slug`
  - Requires JWT auth
  - Frontend preserves slug through auth, then calls the endpoint
  - Resolves slug → therapist
  - Creates or resumes a user-scoped conversation with `assigned_therapist_id` pre-set
  - Returns conversation ID + welcome context

**Tests (RED first):**
- `spec/services/therapist_search_spec.rb`:
  - `it searches by specialty`
  - `it fuzzy-matches by name`
  - `it returns display labels not UUIDs`
  - `it saves selected_therapist_id on confirmation`
  - `it returns empty results for no match`
- `spec/requests/onboard_spec.rb`:
  - `it requires auth`
  - `it resolves valid slug to therapist and creates or resumes a user-scoped conversation`
  - `it returns 404 for invalid slug`
  - `it sets assigned_therapist_id in onboarding progress`

**Critic checkpoint:**
- Auditor: PRD §3.3 routing logic and §4.1 provider matching fully covered
- Security: No raw UUIDs reach LLM context or chat response

---

### Phase 3: Document Processing
**Depends on:** Phase 1. **Parallel with:** Phase 2.

**Goals:**
- `POST /api/agent/documents/upload` — accepts multipart file (with JWT auth), stores it in protected server-side storage, returns `document_ref`
- `DocumentProcessorService`:
  - File allowlist + size validation before storage
  - Enqueue async OCR job after upload
  - File → OCR (stub, same as Python) → field extraction (name, DOB, policy#, group#)
  - `RedactionService.redact_for_llm(raw_text)` before any LLM context
  - Updates `docs_verified` in `OnboardingProgress`
- New `upload_document` tool: LLM references `document_ref` after upload completes
- Raw uploads and raw OCR stored server-side only; redacted summary in conversation messages
- Define purge policy for raw upload/OCR artifacts and background cleanup job

**Tests (RED first):**
- `spec/services/document_processor_spec.rb`:
  - `it extracts fields from insurance card OCR`
  - `it redacts PII before storing in conversation`
  - `it sets docs_verified after successful processing`
  - `it stores raw OCR server-side only`
  - `it handles invalid file types gracefully`
  - `it rejects files exceeding size limit`
- `spec/requests/document_upload_spec.rb`:
  - `it accepts multipart upload with valid auth`
  - `it returns document_ref on success`
  - `it rejects unauthenticated uploads`
  - `it rejects uploads without file`

**Critic checkpoint:** Security Critic audits full PII masking pipeline (upload → OCR → storage → LLM context).

---

### Phase 4: Human Escalation (Stub) + Phantom Booking
**Depends on:** Phase 2 (routing and scheduling tools working). **Two parallel tracks.**

#### Track A — Human Escalation

**Goals:**
- `EscalationService`:
  - Logs escalation event with masked data (`Rails.logger.info`)
  - Clear interface: `EscalationService.escalate(conversation_id:, reason:, risk_level:)`
  - Stub alert method (no-op, ready for webhook/email swap)
- Build on the Phase 1-2 pause/risk primitives instead of introducing them here
- Add background risk accumulator for repeated medium-risk turns (low → medium → crisis)
- Integrates with existing `InputSafetyService` crisis detection and paused-conversation handling

**Tests (RED first):**
- `spec/services/escalation_service_spec.rb`:
  - `it escalates on crisis detection`
  - `it escalates on accumulated medium risk`
  - `it pauses conversation after escalation`
  - `it returns holding message for paused conversations`
  - `it logs escalation without PII`
  - `it does not escalate low-risk conversations`

#### Track B — Phantom Booking

**Goals:**
- When `book_appointment` encounters a slot conflict (already booked by another user), catch the error
- Return apology message to user
- Automatically call `get_available_slots` for refreshed list
- Present updated options

**Tests (RED first):**
- `spec/services/phantom_booking_spec.rb`:
  - `it returns fresh slots on booking conflict`
  - `it includes apology in conflict response`
  - `it succeeds on retry with valid slot`
  - `it handles concurrent booking race condition`

**Critic checkpoint:**
- Security Critic: No PII in escalation logs
- Auditor: PRD §3.2 Human_Escalation and §5.2 Phantom Bookings covered

---

### Phase 5: Frontend Chat UX Enhancements
**Depends on:** Phases 2-3 backend APIs stable. **Parallel with:** Phase 4.

**Goals:**
- Therapist selection cards: render `search_therapists` results as cards with bio, specialty, photo
- Document upload widget: camera/file picker in chat, progress indicator, success confirmation
- Onboarding progress indicator: visual step tracker (intake → documents → therapist → schedule)
- Deep link landing page: `/onboard/:slug` preserves the slug through auth, then calls backend `GET /api/onboard/:slug` and initializes chat
- Update `useChat` hook to handle new response fields and suggested actions
- Update `ChatMessage` to render rich structured content (therapist cards, upload status)

**Files modified/created:**
- `frontend/src/components/chat/ChatWidget.tsx` — layout for progress indicator
- `frontend/src/components/chat/ChatMessage.tsx` — rich card rendering
- `frontend/src/components/chat/TherapistCard.tsx` (new) — therapist selection UI
- `frontend/src/components/chat/DocumentUpload.tsx` (new) — file upload widget
- `frontend/src/components/chat/OnboardingProgress.tsx` (new) — step tracker
- `frontend/src/pages/client/Onboard.tsx` (new) — deep link landing page
- `frontend/src/hooks/useChat.ts` — new state fields, document upload integration
- `frontend/src/App.tsx` — add `/onboard/:slug` route

**Critic checkpoint:** Implementation Critic reviews component structure. Security Critic verifies no PII displayed beyond what backend provides.

---

### Phase 6: Integration & Final Validation
**Depends on:** All prior phases.

**Goals:**
- End-to-end journey tests:
  - Deep link → intake → document upload → therapist search → select → schedule → confirmation
  - Returning user → already onboarded → schedule with existing therapist
  - Crisis during onboarding → escalation → paused → holding message
- Full `rspec` run: parity target is all ~221 existing pytest examples accounted for, plus ~48 new onboarding specs (~269 total examples)
- Run all three critic agents (final sweep)
- Update `STUDY_GUIDE.md`:
  - Describe onboarding assistant and user journeys
  - Node-by-node mapping: PRD LangGraph → Rails service objects
  - Key decisions table
  - Rails migration notes
- Python backend has been removed; Rails is the only backend. Branch history preserved for reference.

**Tests:**
- `spec/integration/onboarding_journey_spec.rb`:
  - `it completes full new user onboarding journey`
  - `it handles returning user with therapist`
  - `it escalates crisis during onboarding`
  - `it handles deep link with valid slug`
  - `it handles phantom booking during scheduling`

---

## TDD & Testing Strategy

### Protocol
1. **Before each phase:** QA Agent creates all new spec files with failing tests (RED). Run `rspec spec/path/to/new_spec.rb` — all must FAIL with expected assertion errors, not syntax/load errors.
2. **During implementation:** After each GREEN step, run the specific spec file. Then run `rspec` (full suite) to check for regressions.
3. **After each phase:** Full `rspec` run. All tests pass. No warnings or deprecations.
4. **At critic checkpoints:** Critics review test quality — testing real behavior, not mocks. Edge cases covered.

### New Spec Files

| File | Topic | Est. Tests |
|------|-------|------------|
| `spec/services/onboarding_routing_spec.rb` | New/returning routing, state persistence | ~8 |
| `spec/services/therapist_search_spec.rb` | Fuzzy search, zero-ID, selection | ~8 |
| `spec/requests/onboard_spec.rb` | Deep link endpoint | ~5 |
| `spec/services/document_processor_spec.rb` | Upload → OCR → redaction pipeline | ~8 |
| `spec/requests/document_upload_spec.rb` | Upload endpoint auth & validation | ~4 |
| `spec/services/escalation_service_spec.rb` | Triggers, pausing, logging | ~6 |
| `spec/services/phantom_booking_spec.rb` | Conflict → retry | ~4 |
| `spec/integration/onboarding_journey_spec.rb` | End-to-end flows | ~5 |
| **Total new** | | **~48** |

Plus all **~221 existing pytest examples** (15 files) ported or superseded by an approved parity mapping = **roughly ~269 total RSpec examples**.

### Existing Python Test Parity Requirement

- Phase 0 must produce a file-by-file parity matrix for every current pytest suite (all 15 files now listed in the Phase 1 test table).
- No current Python test file is silently dropped during migration.
- If a suite is merged, replaced, or intentionally retired, the parity matrix must record where that behavior is covered in Rails before cutover approval.

### PRD Requirements → Test Mapping

| PRD Requirement | Spec File | Key Examples |
|----------------|-----------|--------------|
| §3.3 New User → Intake | `onboarding_routing_spec` | `it routes new users to intake` |
| §3.3 Returning: Needs Therapist | `onboarding_routing_spec` | `it routes returning users without therapist to search` |
| §3.3 Returning: Has Therapist | `onboarding_routing_spec` | `it routes returning users with therapist to scheduling` |
| §4.1 Deep Linking | `onboard_spec` | `it resolves valid slug to therapist` |
| §4.1 Conversational Search | `therapist_search_spec` | `it searches by specialty`, `it fuzzy-matches by name` |
| §4.1 Zero-ID UX | `therapist_search_spec` | `it returns display labels not UUIDs` |
| §4.2 Image-to-Text PII Masking | `document_processor_spec` | `it redacts PII before storing in conversation` |
| §4.2 Scoped Agent Actions | `scheduling_service_spec` (ported) | Existing delegation tests |
| §5.2 Phantom Bookings | `phantom_booking_spec` | `it returns fresh slots on conflict` |
| §3.2 Human Escalation | `escalation_service_spec` | `it escalates on crisis detection` |
| §3.2 Risk Evaluator | `escalation_service_spec` | `it escalates on accumulated medium risk` |

---

## Parallelization Summary

```
Phase 0: Rails Setup & Contracts ──────────────────┐
                                                    │
Phase 1: Chat Agent Pipeline Port ─────────────────┤
                                                    │
                    ┌───────────────────────────────┤
                    │                               │
          Phase 2: Onboarding     Phase 3: Document │
          Routing + Search        Processing        │
                    │                    │          │
                    ├────────────────────┤          │
                    │                               │
          Phase 4: Escalation +   Phase 5: Frontend │
          Phantom Booking         Chat UX           │
                    │                    │          │
                    └────────────────────┘          │
                              │                     │
                    Phase 6: Integration            │
                    & Final Validation ─────────────┘
```

- **Sequential dependencies:** 0 → 1 → 2/3 → 4/5 → 6
- **Parallel within phases:** 2A/2B, 3 with 2, 4A/4B, 5 with 4

---

## Execution Next Steps

Once this plan is approved, begin with Phase 0:

1. ~~Run existing `pytest` to confirm the green Python baseline~~ (Python backend removed)
2. Parity matrix documents route + serializer + test mapping (see `docs/TEST_PARITY_MATRIX.md`)
3. Rails is the sole backend
4. Set up RSpec + FactoryBot + database
5. Create migrations for all models and safety-state fields
6. `GET /health` → 200 on Rails
7. QA Agent writes model specs (RED), then implement models (GREEN)

For every phase thereafter:
- Run `rspec` before changes (baseline)
- QA writes failing tests (RED)
- Implement minimal code (GREEN)
- Refactor while green
- Run `rspec` after (no regressions)
- Invoke relevant critic agents at checkpoint
