# Appointment Assistant - AI Mental Health Treatment Plans
## Implementation Plan v1 — Sequential Build

---

## Technology Stack

| Layer | Choice |
|---|---|
| Database | PostgreSQL (JSONB for plan content) |
| ORM | SQLAlchemy + Alembic |
| Backend | Python + FastAPI |
| AI Provider | Anthropic Claude (Sonnet 4.6) |
| AI Integration | Anthropic SDK (direct, no framework) |
| Frontend | React + Vite + TypeScript |
| Styling | Tailwind CSS + shadcn/ui |
| Auth | JWT (simple, demo-grade) |
| Evaluation | textstat (readability) + Pydantic (structural) |

---

## Architecture Overview

```
Frontend (React + Vite + Tailwind + shadcn/ui)
    │ HTTP / REST / SSE
    ▼
Backend (FastAPI)
    ├── Routes (auth, clients, sessions, plans, safety, evaluation)
    ├── Services (auth, ai_pipeline, plan, safety, evaluation)
    ├── Prompts (therapist_plan, client_view, plan_update)
    └── Models (SQLAlchemy) + Schemas (Pydantic)
    │
    ▼
PostgreSQL (users, clients, sessions, transcripts, plans, versions, flags, homework)
    │
    ▼
Anthropic Claude API (Sonnet 4.6)
```

---

## Domain Model

### Entities
- **User** (id, email, name, role [therapist|client], password_hash)
- **Therapist** (id, user_id FK, license_type, specialties, preferences JSON)
- **Client** (id, user_id FK, therapist_id FK)
- **Session** (id, therapist_id FK, client_id FK, session_date, session_number, duration_minutes, status [pending|processing|completed|error])
- **Transcript** (id, session_id FK, content, source_type [paste|upload], word_count)
- **SessionSummary** (id, session_id FK, therapist_summary, client_summary, key_themes JSON)
- **TreatmentPlan** (id, client_id FK, therapist_id FK, current_version_id FK, status [draft|approved|archived])
- **TreatmentPlanVersion** (id, treatment_plan_id FK, version_number, session_id FK, therapist_content JSONB, client_content JSONB, change_summary, source [ai_generated|ai_updated|therapist_edited|ai_regenerated], ai_metadata JSONB)
- **SafetyFlag** (id, session_id FK, treatment_plan_version_id FK, flag_type, severity, description, transcript_excerpt, transcript_location, source, acknowledged, acknowledged_at, acknowledged_by FK)
- **HomeworkItem** (id, treatment_plan_version_id FK, client_id FK, description, completed, completed_at)

### Key Relationships
- Therapist 1:many Clients
- Client 1:1 TreatmentPlan (active)
- TreatmentPlan 1:many TreatmentPlanVersions
- Session 1:1 Transcript
- Session 1:1 SessionSummary
- TreatmentPlanVersion 1:many SafetyFlags
- TreatmentPlanVersion 1:many HomeworkItems

---

## AI Pipeline

### Two-Stage Generation
1. **Stage 2 — Therapist Plan**: Transcript → Claude Sonnet 4.6 → structured clinical plan with citations + safety flags + session summary
2. **Stage 3 — Client View**: Therapist plan → Claude Sonnet 4.6 → plain-language client-friendly plan

### Safety: Three Layers
1. AI-driven detection (integrated in Stage 2)
2. Programmatic regex backup scan
3. UI safeguards (acknowledgment gate, client view filtering)

### Validation
- Pydantic schema validation on AI output
- Citation line-number bounds checking
- Required fields presence
- Client view jargon detection
- Retry once with error feedback on failure

---

## Treatment Plan Lifecycle
- First session → new plan (draft) → therapist reviews/edits → approves → client sees
- New session → AI updates existing plan → new version (draft) → review → approve
- Manual edits create new version without reverting to draft
- AI updates revert to draft (require re-approval)
- Version history is immutable
- Client always sees latest approved version

---

## Evaluation Framework
- Structural validation (schema compliance, citation validity, jargon-free client view)
- Readability analysis (Flesch-Kincaid grade level, therapist vs client separation)
- Safety detection accuracy (expected vs detected flags per fixture transcript)
- 5-8 synthetic fixture transcripts
- Pre-seeded evaluation results for demo

---

## API Endpoints

### Auth
- POST /api/auth/login
- GET /api/auth/me

### Clients (therapist)
- GET /api/clients
- POST /api/clients
- GET /api/clients/:id

### Sessions
- GET /api/clients/:id/sessions
- POST /api/clients/:id/sessions (text or file upload)
- GET /api/sessions/:id

### Generation
- POST /api/sessions/:id/generate (SSE stream)

### Treatment Plans
- GET /api/clients/:id/treatment-plan
- GET /api/treatment-plans/:id/versions
- GET /api/treatment-plans/:id/versions/:vid
- GET /api/treatment-plans/:id/diff?v1=X&v2=Y
- POST /api/treatment-plans/:id/edit
- POST /api/treatment-plans/:id/approve

### Safety
- GET /api/sessions/:id/safety-flags
- GET /api/clients/:id/safety-flags
- PATCH /api/safety-flags/:id/acknowledge

### Homework (client)
- GET /api/my/homework
- PATCH /api/homework/:id

### Client-Facing
- GET /api/my/treatment-plan
- GET /api/my/sessions
- GET /api/my/sessions/:id

### Evaluation
- POST /api/evaluation/run (SSE)
- GET /api/evaluation/results

---

## Day-by-Day Roadmap

### Day 1: Foundation + AI Pipeline (~10.5 hours)
- 1A: Project scaffolding (1.5h)
- 1B: Database models + migrations (1.5h)
- 1C: Auth minimal (0.5h)
- 1D: AI pipeline core (3.5h)
- 1E: Prompt engineering (1.0h)
- 1F: Session + generation endpoints (1.5h)
- 1G: Synthetic transcripts (1.0h)

### Day 2: Frontend + Core Flows (~10.5 hours)
- 2A: Frontend scaffolding (1.0h)
- 2B: Login page (0.5h)
- 2C: Therapist dashboard (1.0h)
- 2D: Client detail + sessions (1.0h)
- 2E: New session page (1.5h)
- 2F: Plan review page (2.5h)
- 2G: Client dashboard + plan (1.5h)
- 2H: Remaining API endpoints (1.0h)

### Day 3: Lifecycle + Evaluation + Polish (~10.5 hours)
- 3A: Plan editing (1.5h)
- 3B: Versioning + diff (1.5h)
- 3C: Plan update from new session (1.0h)
- 3D: Evaluation framework (2.0h)
- 3E: Seed data (1.0h)
- 3F: Tests (1.0h)
- 3G: README + docs (1.0h)
- 3H: Polish (1.0h)
