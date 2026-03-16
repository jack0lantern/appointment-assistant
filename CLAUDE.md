# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**Tava Health** is an AI-powered mental health treatment plan generation system. The application generates personalized, evidence-based treatment plans for clients using Claude AI, with therapy workflow management and safety evaluation built-in.

**Current Status:** Design & planning phase. The main plan defines a multi-phase orchestrated build using Claude Code agents.

---

## How to Navigate This Repository

### Main Planning Document
- **PLAN_v2_orchestrated.md** — The canonical implementation roadmap
  - Orchestrated multi-agent parallel build strategy
  - Full technology stack (Python/FastAPI backend, React/Vite frontend, PostgreSQL)
  - Day-by-day breakdown with specific tasks and agent responsibilities
  - Shared interfaces/contracts that all agents build against

### Supporting Documents
- **prompts/PLAN_v1_sequential.md** — Alternative sequential build approach (reference only)
- **docs/TavaHealth.pdf** — Product documentation
- **.agents/skills/test-driven-development/** — Custom TDD skill enforcing red-green-refactor discipline

---

## Development Approach

### Test-Driven Development (Mandatory)
This project enforces **strict TDD** via `.agents/skills/test-driven-development/SKILL.md`:

1. **Write failing test first** (RED phase)
2. **Verify it fails correctly** before implementing
3. **Write minimal code to pass** (GREEN phase)
4. **Refactor while green** (REFACTOR phase)

**No exceptions:** All production code must have a failing test written first. If code exists before tests, delete it and start over.

### Orchestrated Parallel Builds
The main plan uses a **main orchestrator** (your Claude Code session) spawning parallel subagents:

- Orchestrator defines shared interfaces/schemas FIRST
- Agents work on isolated units with clear boundaries
- Interdependent work waits; independent work runs in parallel
- Integration checks at each checkpoint

**Key principle:** Shared interfaces (API contracts, Pydantic schemas, database schema) are defined before any agent starts building.

---

## Technology Stack

| Layer | Choice |
|-------|--------|
| **Backend** | Python + FastAPI (async) |
| **ORM** | SQLAlchemy + Alembic (migrations) |
| **Database** | PostgreSQL (JSONB for plan content) |
| **AI Integration** | Anthropic SDK (Claude Sonnet 4.6) |
| **Frontend** | React + Vite + TypeScript |
| **Styling** | Tailwind CSS + shadcn/ui |
| **Auth** | JWT (simple, demo-grade) |
| **Testing** | pytest (backend), TBD (frontend) |
| **Evaluation** | textstat (readability), Pydantic (structural) |

---

## Project Structure (From Plan)

```
backend/
  app/
    models/          # SQLAlchemy ORM models
    schemas/         # Pydantic request/response schemas (CONTRACTS)
    routes/          # FastAPI route handlers
    services/        # Business logic
    prompts/         # AI prompt templates
    utils/           # Shared utilities
  evaluation/        # Treatment plan evaluation logic
  tests/             # Test suite
frontend/            # React/Vite application
docker-compose.yml   # PostgreSQL + backend services
```

---

## Starting New Work

### Phase 1: Foundation (DAY 1)
Per the plan, Phase 1 establishes:
1. Backend scaffolding with FastAPI/SQLAlchemy
2. PostgreSQL with Docker Compose
3. **All Pydantic schemas** (these are the binding contracts for all agents)
4. AI pipeline producing structured treatment plans
5. Database fixtures with demo data

No frontend in Phase 1.

### Shared Contracts
Before any agent builds, ensure these are defined in `backend/app/schemas/`:
- **auth.py** — LoginRequest, LoginResponse, UserResponse
- **client.py** — ClientCreate, ClientResponse
- **session.py** — SessionCreate, SessionResponse, TranscriptResponse
- **treatment_plan.py** — TreatmentPlanResponse, VersionResponse, TherapistPlanContent, ClientPlanContent, Citation, PlanEditRequest, DiffResponse
- **safety.py** — SafetyFlagResponse, FlagType, Severity enums
- **homework.py** — HomeworkItemResponse, HomeworkUpdateRequest
- **evaluation.py** — EvaluationRunResponse, StructuralValidationResult, ReadabilityResult

All agents build to these contracts.

---

## Key Conventions

### Environment Setup
- Create `.env.example` with all required keys (ANTHROPIC_API_KEY, DATABASE_URL, JWT_SECRET, etc.)
- `.env` is git-ignored; developers populate from example

### Database Migrations
- Use Alembic for all schema changes
- Every schema change = a new migration file
- Test migrations up and down

### AI Integration
- Use Anthropic SDK directly (no frameworks)
- Prompts stored in `backend/app/prompts/` as modules
- All AI calls return Pydantic-validated responses

### Testing Pattern (TDD)
1. Write test → watch fail
2. Implement minimal code → watch pass
3. Refactor → keep green
4. Repeat

---

## Commands (When Project is Built)

These will apply once development begins:

```bash
# Backend setup
cd backend
pip install -r requirements.txt
alembic upgrade head  # Run migrations

# Start services
docker-compose up -d  # PostgreSQL
uvicorn app.main:app --reload  # Backend (port 8000)

# Run tests
pytest                    # All tests
pytest path/to/test.py   # Single test file
pytest -k test_name      # Single test

# Linting/formatting (TBD — add when implementation starts)
```

---

## Checkpoints from the Plan

**DAY 1 Checkpoint:**
- Backend API responds at `/health`
- Treatment plan generation works end-to-end
- Database has demo client + session fixtures
- All core schemas validated and tested

**DAY 2 Checkpoint:**
- Frontend builds and connects to backend
- Auth flow (login) works
- Client list page renders

**DAY 3 Checkpoint:**
- Full user journey: login → view plans → request new → generate → display
- Safety evaluation integrated
- Plan versioning works

---

## References & Roles

- **Orchestrator role:** Define contracts, resolve conflicts, verify checkpoints
- **Backend agents:** Build routes, services, models per assigned contracts
- **Frontend agents:** Build pages, components per design spec
- **Evaluation agents:** Build safety checks, readability scoring

Each agent should claim specific tasks from the plan and report status at checkpoints.
