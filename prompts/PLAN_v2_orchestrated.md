# Tava Health - AI Mental Health Treatment Plans
## Implementation Plan v2 — Orchestrated Parallel Build (Claude Code Agents)

---

## Strategy

This plan uses a **main orchestrator** (you, in the root conversation) that spawns
**parallel subagents** to build independent workstreams simultaneously. Each "day"
ends with a checkpoint where the orchestrator verifies correctness and runs manual
tests before proceeding.

### Agent Model

```
ORCHESTRATOR (main Claude Code session)
    │
    ├── Spawns agents in parallel where work is independent
    ├── Waits for results where work has dependencies
    ├── Runs integration checks at each checkpoint
    └── Resolves conflicts when parallel work overlaps
```

### Key Principle
Agents work on **isolated, well-defined units** with **clear interfaces**. When two
agents need to share interfaces (e.g., API schemas), the orchestrator defines the
interface FIRST, then both agents build to that contract.

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

## DAY 1: Foundation + AI Pipeline

### Goal
Backend running, AI pipeline producing structured treatment plans, database seeded
with demo data. No frontend yet.

---

### Step 1.0 — Orchestrator: Scaffolding & Shared Contracts

**Do this yourself (not an agent)** — establishes the foundation all agents build on.
This step is critical: it defines every shared interface that downstream agents
depend on, so they can work in isolation without guessing.

Tasks:
1. Initialize project structure:
   ```
   mkdir -p backend/app/{models,schemas,routes,services,prompts,utils}
   mkdir -p backend/evaluation/fixtures
   mkdir -p backend/tests
   mkdir -p frontend
   ```
2. Create `docker-compose.yml` with PostgreSQL
3. Create `backend/requirements.txt`:
   ```
   fastapi[standard]
   uvicorn[standard]
   sqlalchemy[asyncio]
   asyncpg
   alembic
   anthropic
   python-jose[cryptography]
   passlib[bcrypt]
   python-multipart
   textstat
   pydantic>=2.0
   pydantic-settings
   python-dotenv
   pytest
   pytest-asyncio
   httpx
   ```
4. Create `backend/app/config.py` (Pydantic Settings: DATABASE_URL, ANTHROPIC_API_KEY, JWT_SECRET)
5. Create `backend/app/database.py` (async SQLAlchemy engine + session factory)
6. Create `backend/app/main.py` (FastAPI app with CORS, lifespan for DB)
7. Create `.env.example` and `.env`
8. Create ALL Pydantic schemas in `backend/app/schemas/` — these are the **contracts** agents build against:
   - `schemas/auth.py` — LoginRequest, LoginResponse, UserResponse
   - `schemas/client.py` — ClientCreate, ClientResponse
   - `schemas/session.py` — SessionCreate, SessionResponse, TranscriptResponse
   - `schemas/treatment_plan.py` — TreatmentPlanResponse, VersionResponse, TherapistPlanContent, ClientPlanContent, Citation, PlanEditRequest, DiffResponse
   - `schemas/safety.py` — SafetyFlagResponse, FlagType enum, Severity enum
   - `schemas/homework.py` — HomeworkItemResponse, HomeworkUpdateRequest
   - `schemas/evaluation.py` — EvaluationRunResponse, StructuralValidationResult, ReadabilityResult
   - `schemas/test_analyze.py` — **TranscriptAnalysisRequest / TranscriptAnalysisResponse** (test endpoint contract):
     ```python
     class TranscriptAnalysisRequest(BaseModel):
         transcript_text: str
         client_name: str = "Test Client"          # creates a throw-away client if needed
         save: bool = True                          # if False, runs pipeline but persists nothing

     class TranscriptAnalysisResponse(BaseModel):
         session_id: int | None                     # None when save=False
         treatment_plan_version_id: int | None      # None when save=False
         pipeline_result: PipelineResult            # full raw pipeline output
         safety_flags_detected: int
         homework_items_created: int
         generation_time_seconds: float
     ```
   - `schemas/ai_pipeline.py` — **PipelineResult** schema (the contract between Agent B's AI pipeline and Agent C's generate route):
     ```python
     class PipelineResult(BaseModel):
         therapist_content: TherapistPlanContent
         client_content: ClientPlanContent
         therapist_session_summary: str
         client_session_summary: str
         key_themes: list[str]
         safety_flags: list[SafetyFlagData]  # pre-DB flag data
         homework_items: list[str]           # plain-text descriptions
         change_summary: str | None = None   # only for plan updates
         ai_metadata: dict                   # model, tokens, latency
     ```
9. Create `backend/app/services/auth_service.py` — **must be in Step 1.0** because Agent A's seed.py needs `hash_password`:
   ```python
   from passlib.context import CryptContext
   from jose import jwt
   from datetime import datetime, timedelta
   from app.config import settings

   pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

   def hash_password(password: str) -> str:
       return pwd_context.hash(password)

   def verify_password(plain: str, hashed: str) -> bool:
       return pwd_context.verify(plain, hashed)

   def create_access_token(user_id: int, role: str) -> str:
       expire = datetime.utcnow() + timedelta(hours=24)
       return jwt.encode(
           {"sub": str(user_id), "role": role, "exp": expire},
           settings.JWT_SECRET, algorithm="HS256"
       )

   def decode_token(token: str) -> dict:
       return jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
   ```
10. Create `backend/app/models/base.py` — **must be in Step 1.0** so Agent A and Agent C share the exact same Base:
    ```python
    from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
    from sqlalchemy import DateTime, func
    from datetime import datetime

    class Base(DeclarativeBase):
        pass

    class TimestampMixin:
        created_at: Mapped[datetime] = mapped_column(
            DateTime, server_default=func.now()
        )
        updated_at: Mapped[datetime] = mapped_column(
            DateTime, server_default=func.now(), onupdate=func.now()
        )
    ```
11. Create a **model field name contract** in `backend/app/models/README.md` — agents
    must use these exact names for fields and relationships so imports don't break:
    ```
    ## Model Field Name Contracts

    All agents MUST use these exact field and relationship names.

    ### User
    - id, email, name, role (str: "therapist"|"client"), password_hash
    - Relationships: therapist_profile, client_profile

    ### Therapist
    - id, user_id (FK users.id), license_type, specialties (JSONB), preferences (JSONB)
    - Relationships: user, clients, sessions

    ### Client
    - id, user_id (FK users.id), therapist_id (FK therapists.id), name (str)
    - Relationships: user, therapist, sessions, treatment_plan

    ### Session
    - id, therapist_id (FK), client_id (FK), session_date, session_number, duration_minutes, status (str)
    - Relationships: therapist, client, transcript, summary, safety_flags

    ### Transcript
    - id, session_id (FK unique), content (text), source_type, word_count
    - Relationships: session

    ### SessionSummary
    - id, session_id (FK unique), therapist_summary, client_summary, key_themes (JSONB)
    - Relationships: session

    ### TreatmentPlan
    - id, client_id (FK unique), therapist_id (FK), current_version_id (FK nullable), status (str)
    - Relationships: client, therapist, versions, current_version

    ### TreatmentPlanVersion
    - id, treatment_plan_id (FK), version_number, session_id (FK), therapist_content (JSONB), client_content (JSONB), change_summary, source (str), ai_metadata (JSONB)
    - Relationships: treatment_plan, session, safety_flags, homework_items

    ### SafetyFlag
    - id, session_id (FK), treatment_plan_version_id (FK), flag_type, severity, description, transcript_excerpt, line_start, line_end, source, acknowledged, acknowledged_at, acknowledged_by (FK nullable)
    - Relationships: session, treatment_plan_version

    ### HomeworkItem
    - id, treatment_plan_version_id (FK), client_id (FK), description, completed, completed_at
    - Relationships: treatment_plan_version, client
    ```
12. Create a **minimal test transcript** at `backend/evaluation/fixtures/anxiety.txt`
    (10-15 lines) so Agent B's test script has something to work with immediately.
    Agent D will replace this with a richer version later.
13. Run `docker-compose up -d` and verify Postgres is accessible
14. Initialize Alembic: `alembic init alembic`, configure `alembic/env.py`

**Verify before spawning agents:**
- `docker-compose ps` shows postgres running
- `python -c "from app.config import settings; print(settings.DATABASE_URL)"` works
- All schema files import without errors
- `from app.services.auth_service import hash_password` works
- `from app.models.base import Base, TimestampMixin` works
- `backend/evaluation/fixtures/anxiety.txt` exists

---

### Step 1.1 — Agent A: Database Models + Migrations + Seed (RUN FIRST)

**This agent must complete before Step 1.2 agents can start.** Routes and the
generate endpoint depend on knowing the exact model classes, field names,
and relationship names. Running this first eliminates the #1 integration risk.

Spawn Agent D (Synthetic Transcripts) in **background** in parallel with Agent A
since it has zero code dependencies.

#### Agent A: Database Models + Migrations + Seed

**Prompt:**
```
You are building SQLAlchemy models for a mental health treatment plan application.

Read the following files that have already been created:
- backend/app/schemas/ (all Pydantic schemas — these define the data contracts)
- backend/app/models/base.py (Base and TimestampMixin — already created, use these)
- backend/app/models/README.md (field name contracts — you MUST use these exact names)
- backend/app/services/auth_service.py (already created — use hash_password for seed)

Create the following model files. Use the EXACT field and relationship names
from backend/app/models/README.md:

1. backend/app/models/user.py — User model
2. backend/app/models/therapist.py — Therapist profile
3. backend/app/models/client.py — Client profile (note: has a `name` field for display)
4. backend/app/models/session.py — Session
5. backend/app/models/transcript.py — Transcript
6. backend/app/models/session_summary.py — SessionSummary
7. backend/app/models/treatment_plan.py — TreatmentPlan
8. backend/app/models/treatment_plan_version.py — TreatmentPlanVersion
9. backend/app/models/safety_flag.py — SafetyFlag
10. backend/app/models/homework_item.py — HomeworkItem
11. backend/app/models/__init__.py — Import all models

Then:
12. Generate Alembic migration: alembic revision --autogenerate -m "initial schema"
13. Run migration: alembic upgrade head
14. Create backend/app/seed.py that seeds:
    - Import hash_password from app.services.auth_service
    - Therapist user (email: therapist@tava.health, password: demo123)
    - Client user (email: client@tava.health, password: demo123)
    - Therapist profile (license: LCSW, specialties: ["anxiety", "depression", "CBT"])
    - Client profile linked to therapist (name: "Alex Rivera")
    - 1 session with transcript (read from evaluation/fixtures/anxiety.txt)
15. Run the seed: python -m app.seed

Verify: Connect to postgres and confirm all tables exist and seed data is present.
```

#### Agent D: Fixture Transcripts (run in background, parallel with Agent A)

**Prompt:**
```
Create 5 synthetic therapy session transcripts in backend/evaluation/fixtures/.
These are FICTIONAL transcripts with NO real patient data.
A minimal anxiety.txt may already exist — replace it with a fuller version.

Format: Plain text, therapist/client dialogue, 40-80 lines each.
Use "Therapist:" and "Client:" prefixes for each speaker turn.

1. backend/evaluation/fixtures/anxiety.txt
   - Client with generalized anxiety, work stress, sleep issues
   - Therapist uses CBT techniques
   - NO crisis language
   - Should produce goals around anxiety management

2. backend/evaluation/fixtures/depression.txt
   - Client with moderate depression, low motivation, withdrawal from friends
   - Therapist explores behavioral activation
   - NO crisis language
   - Should produce goals around mood and social engagement

3. backend/evaluation/fixtures/crisis.txt
   - Client expresses passive suicidal ideation ("sometimes think everyone would be better off without me")
   - Client also mentions feeling trapped and hopeless
   - Therapist conducts safety assessment
   - MUST trigger safety flags: suicidal_ideation, severe_distress

4. backend/evaluation/fixtures/substance.txt
   - Client reports increased alcohol use after breakup
   - Mentions drinking 4-5 times per week, blackout once
   - Therapist explores harm reduction
   - MUST trigger safety flags: substance_crisis

5. backend/evaluation/fixtures/relationship.txt
   - Client dealing with conflict in marriage, frustration, anger
   - Therapist works on communication skills
   - NO crisis language (anger != violence — tests false positive resistance)
   - Should NOT trigger safety flags

Make the transcripts feel realistic but clearly synthetic. Include natural
conversation flow, pauses indicated by "...", and therapeutic techniques
being applied.
```

---

### Step 1.2 — Spawn TWO agents in parallel (AFTER Agent A completes)

Once Agent A finishes and models + seed are verified, spawn these simultaneously.
Both depend on the models existing but do NOT depend on each other.

#### Agent B: AI Pipeline Service

**Prompt:**
```
You are building the AI pipeline service that converts therapy session transcripts
into structured treatment plans using the Anthropic Claude API.

Read the following files that already exist:
- backend/app/schemas/treatment_plan.py (TherapistPlanContent, ClientPlanContent, Citation)
- backend/app/schemas/safety.py (FlagType enum, Severity enum)
- backend/app/schemas/ai_pipeline.py (PipelineResult — you MUST return this exact type)
- backend/app/models/ (all SQLAlchemy models — read to understand the data structures)

Create the following files:

1. backend/app/prompts/therapist_plan.py
   - SYSTEM_PROMPT: Clinical documentation assistant instructions
   - Build the user prompt template that takes: numbered_transcript, therapist_preferences (optional), existing_plan (optional for updates)
   - Include a truncated few-shot example showing correct citation format
   - Request JSON output matching TherapistPlanContent schema

2. backend/app/prompts/client_view.py
   - SYSTEM_PROMPT: Compassionate health communication specialist
   - Takes therapist plan JSON as input
   - Outputs ClientPlanContent schema
   - Also generates client-friendly session summary

3. backend/app/prompts/plan_update.py
   - Modified therapist prompt for updating existing plans
   - Takes existing plan + new transcript
   - Generates change_summary

4. backend/app/utils/safety_patterns.py
   - SAFETY_PATTERNS dict mapping FlagType enum to lists of compiled regex patterns
   - Categories: suicidal_ideation, self_harm, harm_to_others, substance_crisis, severe_distress
   - scan_transcript_for_safety(lines, existing_ai_flags) function
   - Deduplication: skip if line range overlaps with existing AI flag

5. backend/app/services/ai_pipeline.py
   - preprocess_transcript(content: str) -> tuple[str, list[str]]
     Returns (numbered_transcript_text, lines_list)
   - async generate_therapist_plan(transcript: str, preferences: dict | None, existing_plan: dict | None) -> TherapistPlanContent
     Calls Claude Sonnet via anthropic SDK with tool_use for structured output
     Temperature: 0.3
     Validates output against Pydantic schema
     Retry once on validation failure
   - async generate_client_view(therapist_plan: dict) -> ClientPlanContent
     Second Claude call, temperature: 0.5
   - async run_pipeline(transcript_content: str, preferences: dict | None = None, existing_plan: dict | None = None) -> PipelineResult
     Orchestrates: preprocess → therapist plan → client view → safety regex scan → validate
     MUST return PipelineResult from app.schemas.ai_pipeline (already defined)

Use the anthropic Python SDK. Model: claude-sonnet-4-6.
For structured output, use the messages API with a strong JSON prompt and parse with Pydantic.
Handle errors: API timeouts (return error), malformed JSON (attempt repair, retry once), missing fields (fill with "Insufficient data").

Do NOT create any route files or database calls. This service is pure AI logic.

Test by creating a small script backend/test_pipeline.py that:
- Reads a transcript from evaluation/fixtures/anxiety.txt (it already exists)
- Runs the pipeline
- Prints the structured output
- Verifies it parses into the Pydantic schemas
```

#### Agent C: Dependencies + Route Structure

**Prompt:**
```
You are building the route structure for a FastAPI mental health treatment plan
application.

Read the following files that already exist:
- backend/app/schemas/ (all Pydantic request/response types)
- backend/app/schemas/ai_pipeline.py (PipelineResult — the return type of the AI pipeline)
- backend/app/models/ (all SQLAlchemy models — use these for DB queries)
- backend/app/models/README.md (field name contracts)
- backend/app/services/auth_service.py (already created — use verify_password, create_access_token, decode_token)
- backend/app/database.py (async session factory)

IMPORTANT: auth_service.py already exists. Do NOT recreate it.

Create:

1. backend/app/dependencies.py
   - get_db() -> async generator yielding DB session
   - get_current_user(token from Authorization header) -> User
     Import decode_token from app.services.auth_service
     Query User model from database
   - require_therapist(current_user) -> User (raises 403 if not therapist)
   - require_client(current_user) -> User (raises 403 if not client)

2. backend/app/routes/auth.py
   - POST /api/auth/login — use verify_password from auth_service, return JWT + user info
   - GET /api/auth/me — return current user from token

3. backend/app/routes/clients.py (therapist only)
   - GET /api/clients — list clients for logged-in therapist
   - POST /api/clients — create new client (just name)
   - GET /api/clients/{client_id} — client detail with recent sessions and active plan summary

4. backend/app/routes/sessions.py
   - GET /api/clients/{client_id}/sessions — list sessions
   - POST /api/clients/{client_id}/sessions — create session with transcript (accept JSON body with transcript_text, or multipart with .txt file)
   - GET /api/sessions/{session_id} — session detail with transcript, summary, flags

5. backend/app/routes/treatment_plans.py
   - GET /api/clients/{client_id}/treatment-plan — current plan with latest version
   - GET /api/treatment-plans/{plan_id}/versions — version list
   - GET /api/treatment-plans/{plan_id}/versions/{version_id} — version detail
   - POST /api/treatment-plans/{plan_id}/edit — therapist edits (creates new version)
   - POST /api/treatment-plans/{plan_id}/approve — approve plan (checks safety flags acknowledged)
   - GET /api/treatment-plans/{plan_id}/diff — query params v1, v2, returns section diffs

6. backend/app/routes/safety.py
   - GET /api/sessions/{session_id}/safety-flags
   - GET /api/clients/{client_id}/safety-flags
   - PATCH /api/safety-flags/{flag_id}/acknowledge

7. backend/app/routes/homework.py
   - GET /api/my/homework — client's active homework
   - PATCH /api/homework/{item_id} — toggle completion

8. backend/app/routes/client_routes.py (client-facing, /api/my/*)
   - GET /api/my/treatment-plan — client's approved plan (client_content only)
   - GET /api/my/sessions — client's sessions with client summaries
   - GET /api/my/sessions/{session_id} — single session client summary

9. Register all routers in main.py (read main.py first, add router includes)

10. backend/app/routes/test_analyze.py — **test/dev endpoint for direct transcript analysis**
    - POST /api/test/analyze (no auth required — dev/demo only)
    - Accepts JSON body matching TranscriptAnalysisRequest schema
    - Also accepts multipart/form-data with a .txt file upload (field: `file`) and
      optional form fields `client_name` and `save` — so curl with `-F file=@transcript.txt` works
    - Flow:
      1. Start timer
      2. If `save=True`: look up or create a demo therapist (email: therapist@tava.health),
         create a Client with `client_name`, create a Session + Transcript record
      3. Call `run_pipeline(transcript_text)` from app.services.ai_pipeline
      4. If `save=True`: persist TreatmentPlan, TreatmentPlanVersion, SafetyFlag, HomeworkItem, SessionSummary
      5. Return TranscriptAnalysisResponse with full pipeline_result and summary stats
    - On error: return HTTP 422 with detail showing which pipeline stage failed
    - **This route is intentionally unauthenticated** — it exists solely for rapid testing
      and demo walkthroughs. Add a comment: `# DEV ONLY — remove or auth-gate for production`

For the generation endpoint:
11. backend/app/routes/generate.py
    - POST /api/sessions/{session_id}/generate
    - Returns SSE (StreamingResponse with text/event-stream)
    - Import run_pipeline from app.services.ai_pipeline (it will exist from Agent B)
    - run_pipeline returns PipelineResult (defined in app.schemas.ai_pipeline — read it for exact fields)
    - Unpack PipelineResult to create DB records:
      * TreatmentPlanVersion (therapist_content, client_content, change_summary, ai_metadata)
      * SafetyFlag records (from pipeline_result.safety_flags)
      * HomeworkItem records (from pipeline_result.homework_items)
      * SessionSummary (therapist_summary, client_summary, key_themes)
    - If client has existing plan: create new version (ai_updated), revert plan to draft
    - If no existing plan: create TreatmentPlan + first version (ai_generated)
    - Wrap each stage with SSE progress events

For routes that do basic CRUD, implement them fully with database queries.
Use the model field names exactly as defined in backend/app/models/ (read the model files).
Use the dependencies from dependencies.py for auth.
```

---

### Step 1.2Q — QA Agent: Verify Day 1 Agent Output

**Spawn after Agents A, B, C, and D complete (before integration).**

This agent reads every file the build agents produced, checks it against the
spec, and reports a structured pass/fail checklist. The orchestrator uses the
report to decide whether to proceed to integration or send work back.

#### Agent QA-1: Day 1 Quality Gate

**Prompt:**
```
You are a QA reviewer for a mental health treatment plan application. Your ONLY
job is to verify that Agents A, B, C, and D produced code that matches the
specification. Do NOT fix anything — just report what passes and what fails.

Read every file listed below and check the criteria. Return a structured report
in this exact format for each agent:

## Agent A — Database Models + Migrations + Seed
Files to check:
- backend/app/models/*.py (all model files)
- backend/app/models/__init__.py
- backend/app/seed.py
- alembic/versions/ (at least one migration file)

Checks:
- [ ] Every model file exists per spec (user, therapist, client, session,
      transcript, session_summary, treatment_plan, treatment_plan_version,
      safety_flag, homework_item)
- [ ] __init__.py imports ALL models
- [ ] Field names match backend/app/models/README.md EXACTLY (compare field by
      field — flag any deviation)
- [ ] Relationship names match README.md EXACTLY
- [ ] All models inherit from Base (from app.models.base) and use TimestampMixin
      where appropriate
- [ ] Foreign keys reference correct tables
- [ ] seed.py imports hash_password from app.services.auth_service (not its own)
- [ ] seed.py creates: therapist user, client user, therapist profile, client
      profile, 1 session with transcript from evaluation/fixtures/anxiety.txt
- [ ] seed.py uses correct credentials (therapist@tava.health / demo123,
      client@tava.health / demo123)
- [ ] At least one Alembic migration file exists

## Agent B — AI Pipeline Service
Files to check:
- backend/app/prompts/therapist_plan.py
- backend/app/prompts/client_view.py
- backend/app/prompts/plan_update.py
- backend/app/utils/safety_patterns.py
- backend/app/services/ai_pipeline.py
- backend/test_pipeline.py

Checks:
- [ ] therapist_plan.py has SYSTEM_PROMPT and user prompt template
- [ ] client_view.py has SYSTEM_PROMPT, takes therapist plan as input
- [ ] plan_update.py handles existing plan + new transcript
- [ ] safety_patterns.py maps FlagType enum values to compiled regex patterns
- [ ] safety_patterns.py has scan_transcript_for_safety() with deduplication
- [ ] ai_pipeline.py exports: preprocess_transcript, generate_therapist_plan,
      generate_client_view, run_pipeline
- [ ] run_pipeline returns PipelineResult (from app.schemas.ai_pipeline)
- [ ] ai_pipeline.py uses anthropic SDK with model claude-sonnet-4-6
- [ ] ai_pipeline.py uses temperature 0.3 for therapist, 0.5 for client
- [ ] ai_pipeline.py has retry-once on validation failure
- [ ] test_pipeline.py reads from evaluation/fixtures/anxiety.txt
- [ ] No route files or database calls in ai_pipeline.py (pure AI logic)

## Agent C — Dependencies + Route Structure
Files to check:
- backend/app/dependencies.py
- backend/app/routes/auth.py
- backend/app/routes/clients.py
- backend/app/routes/sessions.py
- backend/app/routes/treatment_plans.py
- backend/app/routes/safety.py
- backend/app/routes/homework.py
- backend/app/routes/client_routes.py
- backend/app/routes/generate.py
- backend/app/routes/test_analyze.py
- backend/app/main.py (check router registrations)

Checks:
- [ ] dependencies.py has: get_db, get_current_user, require_therapist,
      require_client
- [ ] get_current_user imports decode_token from app.services.auth_service
- [ ] auth.py has POST /api/auth/login and GET /api/auth/me
- [ ] auth.py imports verify_password and create_access_token from
      app.services.auth_service (does NOT redefine them)
- [ ] clients.py has GET /api/clients, POST /api/clients,
      GET /api/clients/{client_id}
- [ ] sessions.py has GET /api/clients/{client_id}/sessions,
      POST /api/clients/{client_id}/sessions,
      GET /api/sessions/{session_id}
- [ ] treatment_plans.py has GET .../treatment-plan, GET .../versions,
      GET .../versions/{version_id}, POST .../edit, POST .../approve,
      GET .../diff
- [ ] safety.py has GET .../safety-flags (by session and by client),
      PATCH .../acknowledge
- [ ] homework.py has GET /api/my/homework, PATCH /api/homework/{item_id}
- [ ] client_routes.py has GET /api/my/treatment-plan, GET /api/my/sessions,
      GET /api/my/sessions/{session_id}
- [ ] generate.py has POST /api/sessions/{session_id}/generate with SSE
- [ ] generate.py imports run_pipeline from app.services.ai_pipeline
- [ ] generate.py unpacks PipelineResult to create DB records
      (TreatmentPlanVersion, SafetyFlag, HomeworkItem, SessionSummary)
- [ ] test_analyze.py exists at backend/app/routes/test_analyze.py
- [ ] test_analyze.py has POST /api/test/analyze with no auth requirement
- [ ] test_analyze.py accepts both JSON body and multipart file upload
- [ ] test_analyze.py respects `save=False` (runs pipeline, persists nothing)
- [ ] test_analyze.py returns TranscriptAnalysisResponse with pipeline_result,
      safety_flags_detected, homework_items_created, generation_time_seconds
- [ ] test_analyze.py has DEV ONLY comment
- [ ] All routers registered in main.py
- [ ] Model field names used in queries match backend/app/models/README.md

## Agent D — Fixture Transcripts
Files to check:
- backend/evaluation/fixtures/anxiety.txt
- backend/evaluation/fixtures/depression.txt
- backend/evaluation/fixtures/crisis.txt
- backend/evaluation/fixtures/substance.txt
- backend/evaluation/fixtures/relationship.txt

Checks:
- [ ] All 5 files exist
- [ ] Each file is 40-80 lines
- [ ] Each uses "Therapist:" and "Client:" speaker prefixes
- [ ] crisis.txt contains passive suicidal ideation language
- [ ] substance.txt contains increased alcohol use / blackout language
- [ ] relationship.txt has anger/conflict but NO crisis language
- [ ] anxiety.txt and depression.txt have NO crisis language

## Cross-Agent Consistency
- [ ] All model imports in route files match the actual model class names in
      backend/app/models/__init__.py
- [ ] All schema imports in route files match the actual schema class names in
      backend/app/schemas/
- [ ] PipelineResult fields used in generate.py match the PipelineResult schema
      definition in backend/app/schemas/ai_pipeline.py
- [ ] auth_service.py is NOT duplicated (only one copy in
      backend/app/services/auth_service.py)
- [ ] base.py is NOT duplicated (only one copy in backend/app/models/base.py)

Report format:
For each check, output ✅ PASS or ❌ FAIL with a one-line explanation for
failures. At the end, output a summary: total checks, passed, failed, and a
list of blocking issues that must be fixed before integration.
```

---

### Step 1.3 — Orchestrator: Integration

After QA-1 passes (fix any blocking issues first), then proceed.
After Agents B and C complete (and Agent D if it hasn't finished yet, just
ensure the fixture transcripts are present):

1. **Verify no import conflicts**: Run `python -c "from app.main import app"`
2. **Check Agent B's pipeline works**: `cd backend && python test_pipeline.py`
3. **Start server**: `uvicorn app.main:app --reload`
4. **Fix any integration issues** — likely spots:
   - Agent C's generate route importing `run_pipeline` from Agent B's module
   - Agent C's route models matching Agent A's model field names
   - Router registration in main.py
   - Circular imports between models and schemas

---

### DAY 1 CHECKPOINT — Manual Testing

**Before proceeding to Day 2, verify all of the following:**

#### 1. Infrastructure
```bash
# Postgres is running
docker-compose ps

# All tables exist
docker-compose exec postgres psql -U postgres -d tava -c "\dt"
# Expected: users, therapists, clients, sessions, transcripts,
#           session_summaries, treatment_plans, treatment_plan_versions,
#           safety_flags, homework_items
```

#### 2. Seed Data
```bash
# Seed exists
docker-compose exec postgres psql -U postgres -d tava -c \
  "SELECT id, email, role FROM users;"
# Expected: therapist@tava.health (therapist), client@tava.health (client)

docker-compose exec postgres psql -U postgres -d tava -c \
  "SELECT id, user_id FROM therapists;"
# Expected: 1 row

docker-compose exec postgres psql -U postgres -d tava -c \
  "SELECT id, therapist_id FROM clients;"
# Expected: 1 row
```

#### 3. Auth
```bash
# Start server
uvicorn app.main:app --reload --port 8000

# Login as therapist
curl -s -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"therapist@tava.health","password":"demo123"}' | python -m json.tool
# Expected: { "token": "eyJ...", "user": { "id": 1, "email": "...", "role": "therapist" } }

# Save token
export TOKEN="<paste token here>"

# Get current user
curl -s http://localhost:8000/api/auth/me \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Expected: user object

# Login as client
curl -s -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"client@tava.health","password":"demo123"}' | python -m json.tool
```

#### 4. Client CRUD
```bash
# List clients (as therapist)
curl -s http://localhost:8000/api/clients \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Expected: array with 1 client

# Create new client
curl -s -X POST http://localhost:8000/api/clients \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Jane Smith"}' | python -m json.tool
# Expected: new client object
```

#### 5. Session + Transcript Creation
```bash
# Create session with pasted transcript (use client_id from step 4)
curl -s -X POST http://localhost:8000/api/clients/1/sessions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "transcript_text": "Therapist: How have you been feeling this week?\nClient: Not great, honestly. I have been really anxious about work.\nTherapist: Tell me more about that.\nClient: I just feel like I can never catch up. My mind races at night and I cannot sleep.",
    "session_date": "2026-03-15",
    "duration_minutes": 50
  }' | python -m json.tool
# Expected: session object with status: "pending"
```

#### 6. Test Analyze Endpoint (QUICK PIPELINE SMOKE TEST)
```bash
# Dry run — no DB writes, just verify pipeline runs end-to-end
curl -s -X POST http://localhost:8000/api/test/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "transcript_text": "Therapist: How have you been this week?\nClient: Pretty anxious. Cannot sleep and my mind keeps racing.\nTherapist: Tell me more about the racing thoughts.\nClient: I keep worrying about work deadlines and disappointing my team.",
    "save": false
  }' | python -m json.tool
# Expected: pipeline_result with therapist_content + client_content, safety_flags_detected: 0

# Same test but with a file upload (useful for testing fixture transcripts)
curl -s -X POST http://localhost:8000/api/test/analyze \
  -F "file=@backend/evaluation/fixtures/anxiety.txt" \
  -F "client_name=Smoke Test Client" \
  -F "save=false" | python -m json.tool

# Full run with DB save — creates client, session, plan, homework in one shot
curl -s -X POST http://localhost:8000/api/test/analyze \
  -F "file=@backend/evaluation/fixtures/crisis.txt" \
  -F "client_name=Crisis Test Client" \
  -F "save=true" | python -m json.tool
# Expected: session_id and treatment_plan_version_id populated, safety_flags_detected >= 1

# Verify the saved data exists
curl -s http://localhost:8000/api/clients \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Expected: "Crisis Test Client" appears in the list
```

#### 7. AI Pipeline (THE CRITICAL TEST)
```bash
# NOTE: The seed may have created session id=1 already. Use the session id
# returned from Step 5, or check:
curl -s http://localhost:8000/api/clients/1/sessions \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Note the session ID (e.g., SESSION_ID=2 if seed created id=1)

# Generate treatment plan (SSE stream) — use the correct session ID
export SESSION_ID=<id from above>
curl -N -X POST http://localhost:8000/api/sessions/$SESSION_ID/generate \
  -H "Authorization: Bearer $TOKEN"
# Expected: SSE events streaming:
#   event: progress
#   data: {"stage": "preprocessing", "message": "Preparing transcript..."}
#   ...
#   event: complete
#   data: {"session_id": ..., "treatment_plan_version_id": ..., ...}

# Verify plan was created
curl -s http://localhost:8000/api/clients/1/treatment-plan \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Expected: treatment plan with therapist_content containing:
#   presenting_concerns, goals, interventions, homework, strengths
#   Each with citations array containing line_start, line_end, text

# Verify session summary was created
curl -s http://localhost:8000/api/sessions/$SESSION_ID \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Expected: session with summary (therapist_summary + client_summary)
```

#### 8. Safety Detection (use crisis transcript)
```bash
# Create session with crisis transcript
curl -s -X POST http://localhost:8000/api/clients/1/sessions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcript_text\": $(cat backend/evaluation/fixtures/crisis.txt | python -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),
    \"session_date\": \"2026-03-16\",
    \"duration_minutes\": 50
  }" | python -m json.tool
# Note the returned session ID as CRISIS_SESSION_ID

# Generate and check for safety flags
export CRISIS_SESSION_ID=<id from above>
curl -N -X POST http://localhost:8000/api/sessions/$CRISIS_SESSION_ID/generate \
  -H "Authorization: Bearer $TOKEN"

# Check safety flags
curl -s http://localhost:8000/api/sessions/$CRISIS_SESSION_ID/safety-flags \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
# Expected: at least 1 safety flag with type suicidal_ideation or severe_distress
```

#### 9. Fixture Transcripts Exist
```bash
ls -la backend/evaluation/fixtures/
# Expected: anxiety.txt, depression.txt, crisis.txt, substance.txt, relationship.txt
wc -l backend/evaluation/fixtures/*.txt
# Expected: 40-80 lines each
```

#### Day 1 Pass Criteria
- [ ] Postgres running with all tables
- [ ] Demo users seeded and can log in
- [ ] Session creation with transcript works
- [ ] AI pipeline generates structured treatment plan with citations
- [ ] Client view is generated (plain language, no jargon)
- [ ] Safety flags detected for crisis transcript
- [ ] 5 fixture transcripts exist
- [ ] No import errors, server starts cleanly
- [ ] POST /api/test/analyze works with JSON body (save=false) — no auth required
- [ ] POST /api/test/analyze works with file upload (save=true) — creates full DB records
- [ ] test/analyze response includes pipeline_result, safety_flags_detected, generation_time_seconds

---

## DAY 2: Frontend + Core Flows

### Goal
Both dashboards functional. End-to-end browser flow covers transcript input,
generation, therapist review/edit/approval, and client viewing/homework.

---

### Step 2.0 — Orchestrator: Frontend Scaffolding

**Do this yourself** — establishes shared config all frontend agents build on.
This step also defines ALL routes and ALL shared TypeScript types, so the two
page-building agents never need to touch each other's files.

Tasks:
1. `cd frontend && npm create vite@latest . -- --template react-ts`
2. Install dependencies:
   ```
   npm install react-router-dom axios @tanstack/react-query
   npm install -D tailwindcss @tailwindcss/vite
   npx shadcn@latest init
   ```
3. Add shadcn components needed:
   ```
   npx shadcn@latest add button card input label textarea badge
   npx shadcn@latest add dialog sheet tabs table separator
   npx shadcn@latest add alert dropdown-menu avatar checkbox
   npx shadcn@latest add toast progress skeleton
   ```
4. Create `frontend/src/api/client.ts`:
   - Axios instance with baseURL `http://localhost:8000`
   - Request interceptor to attach JWT from localStorage
   - Response interceptor for 401 → redirect to login
   - Also create `frontend/src/lib/sse.ts` with a small helper for consuming
     POST-based streamed responses via `fetch()` + `ReadableStream`, because
     browser `EventSource` cannot POST. Agents E and H should both reuse this
     helper for `/api/sessions/{id}/generate` and `/api/evaluation/run`.
5. Create `frontend/src/types/index.ts` — **shared TypeScript types matching backend
   Pydantic schemas** so both agents use the same types instead of inventing their own:
   ```typescript
   // Auth
   export interface User { id: number; email: string; name: string; role: 'therapist' | 'client' }
   export interface LoginResponse { token: string; user: User }

   // Client (the patient entity, not HTTP client)
   export interface ClientProfile { id: number; name: string; therapist_id: number; session_count?: number; last_session_date?: string; has_safety_flags?: boolean }

   // Session
   export interface Session { id: number; client_id: number; therapist_id: number; session_date: string; session_number: number; duration_minutes: number; status: string; summary?: SessionSummary }
   export interface SessionSummary { therapist_summary: string; client_summary: string; key_themes: string[] }

   // Treatment Plan
   export interface TreatmentPlan { id: number; client_id: number; status: string; current_version?: TreatmentPlanVersion; versions?: TreatmentPlanVersion[] }
   export interface TreatmentPlanVersion { id: number; version_number: number; session_id: number; therapist_content: TherapistPlanContent; client_content: ClientPlanContent; change_summary: string; source: string; created_at: string }

   // Plan content structures
   export interface Citation { text: string; line_start: number; line_end: number }
   export interface PlanItem { content: string; citations?: Citation[] }
   export interface TherapistPlanContent {
     presenting_concerns: PlanItem[]; clinical_impressions: PlanItem;
     goals: { short_term: PlanItem[]; long_term: PlanItem[] };
     interventions: (PlanItem & { modality: string })[];
     homework: PlanItem[]; strengths: PlanItem[];
     risk_indicators: (PlanItem & { severity: string })[];
   }
   export interface ClientPlanContent {
     what_were_working_on: { content: string }[];
     your_goals: { short_term: { content: string }[]; long_term: { content: string }[] };
     our_approach: { content: string }[];
     things_to_try: { content: string }[];
     your_strengths: { content: string }[];
   }

   // Safety
   export interface SafetyFlag { id: number; flag_type: string; severity: string; description: string; transcript_excerpt: string; line_start: number; line_end: number; source: string; acknowledged: boolean }

   // Homework
   export interface HomeworkItem { id: number; description: string; completed: boolean; completed_at?: string }

   // SSE
   export interface GenerationProgress { stage: string; message: string }
   ```
6. Create `frontend/src/context/AuthContext.tsx`:
   - AuthProvider wrapping app
   - login(email, password), logout()
   - user state (User type from types/index.ts)
   - Token stored in localStorage
7. Create `frontend/src/App.tsx` — **define ALL routes with placeholder components**.
   Agents E and F will create the page files; they must NOT modify App.tsx:
   ```tsx
   // ALL routes defined here.
   // Include a public /login route and a root redirect to /login.
   // Use inline placeholders or stub page files so the app can boot before
   // agent-generated pages exist. Do NOT import files that don't exist yet.
   // Therapist routes
   /therapist/clients → TherapistDashboard
   /therapist/dashboard → TherapistDashboard
   /therapist/clients/:clientId → ClientDetail
   /therapist/sessions/new → NewSession
   /therapist/clients/:clientId/plan → PlanReview
   /therapist/evaluation → Evaluation

   // Client routes
   /client/dashboard → ClientDashboard
   /client/plan → PlanView
   /client/sessions → Sessions
   /client/homework → Homework
   ```
   The app should remain bootable immediately after Step 2.0. Do not rely on
   missing imports that intentionally crash the dev server.
8. Create `frontend/src/layouts/TherapistLayout.tsx`:
   - Left sidebar: Dashboard, Clients, Evaluation
   - Top bar: user name, logout button
   - `<Outlet />` for page content
9. Create `frontend/src/layouts/ClientLayout.tsx`:
   - Top nav: My Plan, Sessions, Homework
   - Warmer styling (teal accents, rounded corners)
   - `<Outlet />` for page content
10. Create `frontend/src/components/shared/PrivacyDisclaimer.tsx`:
    - Persistent footer on every page
    - "AI-generated content — not a substitute for professional clinical judgment."
    - 988 crisis line reference
11. Create `frontend/src/pages/Login.tsx`:
    - Email + password form
    - Login button → calls auth context login
    - Redirects based on role
12. Verify: `npm run dev` shows login page, can log in as therapist, sees sidebar layout

---

### Step 2.1 — Spawn TWO agents in parallel

#### Agent E: Therapist Pages

**Prompt:**
```
You are building the therapist-facing pages for a mental health treatment plan
React application. The project uses React + Vite + TypeScript + Tailwind CSS +
shadcn/ui + React Router + TanStack React Query.

Read the existing files FIRST:
- frontend/src/types/index.ts (ALL TypeScript types — import from here, do NOT define your own interfaces)
- frontend/src/api/client.ts (API client)
- frontend/src/context/AuthContext.tsx (auth)
- frontend/src/layouts/TherapistLayout.tsx (layout structure)
- frontend/src/App.tsx (routes — DO NOT MODIFY THIS FILE, routes are already defined)

IMPORTANT:
- All TypeScript types are already defined in frontend/src/types/index.ts. Import them.
- Routes are already registered in App.tsx. Do NOT modify App.tsx.
- Only create page and component files.
- PRD alignment: therapist review + edit is a Day 2 core flow, not a Day 3 stretch.

Create the following pages and components:

1. frontend/src/pages/therapist/Dashboard.tsx
   - Fetch GET /api/clients
   - Display client list as cards (ClientCard component)
   - Each card shows: client name, number of sessions, "last session" date
   - If client has unacknowledged safety flags, show red badge
   - "Add Client" button → inline form (just name field)
   - Empty state when no clients

2. frontend/src/pages/therapist/ClientDetail.tsx
   - Fetch GET /api/clients/{id} (includes sessions + active plan summary)
   - Client name header
   - Session history table: date, session number, status, safety flag count
   - "New Session" button → navigates to NewSession page
   - Current treatment plan summary card (status, last updated, version count)
   - Click plan card → navigates to PlanReview

3. frontend/src/pages/therapist/NewSession.tsx
   - Form: select client (dropdown if coming from dashboard) or pre-filled if coming from ClientDetail
   - Session date picker (default today)
   - Duration input (default 50 min)
   - TranscriptUpload component:
     - Tab: "Paste" → large textarea with line count display
     - Tab: "Upload" → drag-and-drop zone for .txt files, reads file content
   - "Generate Treatment Plan" button
   - On submit: POST /api/clients/{id}/sessions, then POST /api/sessions/{id}/generate
   - GenerationProgress component:
     - Full-screen overlay/modal
     - 4 stages shown as steps: Preparing → Analyzing → Generating Client View → Validating
     - Consumes the streamed POST response via the shared `frontend/src/lib/sse.ts`
       helper, updates stages in real-time
     - On "complete" event: navigate to PlanReview page
     - On "error" event: show error message with retry button

4. frontend/src/pages/therapist/PlanReview.tsx
   - Fetch GET /api/clients/{id}/treatment-plan
   - SafetyFlagBanner at top (if flags exist):
     - Red/amber banner, non-dismissable
     - Each flag: type badge, severity, transcript excerpt, line reference
     - "Acknowledge" button per flag → PATCH /api/safety-flags/{id}/acknowledge
     - Message: "You must acknowledge all safety flags before approving"
   - Session summary card (therapist_summary text)
   - Treatment plan sections, each as a PlanSection component:
     - Presenting Concerns
     - Clinical Impressions
     - Short-Term Goals
     - Long-Term Goals
     - Interventions & Approaches
     - Homework / Between-Session Actions
     - Strengths & Protective Factors
     - Risk Indicators (if any)
   - Each PlanSection has:
     - Section title
     - Content display
     - "Show Citations" button → opens CitationSidebar
     - "Edit" button → switches to textarea edit mode with Save/Cancel
     - Save → POST /api/treatment-plans/{id}/edit, refresh current plan data,
       keep the plan in draft until therapist approval
   - CitationSidebar (Sheet component from shadcn):
     - Slides in from right
     - Shows transcript excerpts with line numbers
     - Highlighted text
   - Action buttons at bottom:
     - "Approve & Share with Client" (disabled if unacknowledged flags)
       → POST /api/treatment-plans/{id}/approve
     - "Save as Draft" (implicit, plan is already draft)
   - Plan status badge (draft/approved)

5. frontend/src/pages/therapist/Evaluation.tsx
   - Placeholder for now (just a card saying "Evaluation Dashboard — Coming in Day 3")

Create supporting components in frontend/src/components/therapist/:
- ClientCard.tsx
- TranscriptUpload.tsx
- GenerationProgress.tsx
- PlanSection.tsx
- CitationSidebar.tsx
- SafetyFlagBanner.tsx
- SessionSummaryCard.tsx

Use TanStack React Query for all data fetching (useQuery, useMutation).
Use the existing api/client.ts for HTTP calls.
Import ALL types from frontend/src/types/index.ts.
Style with Tailwind + shadcn components. Therapist UI should feel professional:
slate/gray backgrounds, blue accents, data-dense.
```

#### Agent F: Client Pages

**Prompt:**
```
You are building the client-facing pages for a mental health treatment plan
React application. The project uses React + Vite + TypeScript + Tailwind CSS +
shadcn/ui + React Router + TanStack React Query.

Read the existing files FIRST:
- frontend/src/types/index.ts (ALL TypeScript types — import from here, do NOT define your own interfaces)
- frontend/src/api/client.ts (API client)
- frontend/src/context/AuthContext.tsx (auth)
- frontend/src/layouts/ClientLayout.tsx (layout structure)
- frontend/src/App.tsx (routes — DO NOT MODIFY THIS FILE, routes are already defined)

IMPORTANT:
- All TypeScript types are already defined in frontend/src/types/index.ts. Import them.
- Routes are already registered in App.tsx. Do NOT modify App.tsx.
- Only create page and component files.

Create the following pages and components:

1. frontend/src/pages/client/Dashboard.tsx
   - Warm welcome message: "Welcome back, {name}" with current date
   - Privacy disclaimer card at top (friendly tone):
     "This plan was created by your therapist with AI assistance. If you have
      questions, please bring them up in your next session."
   - "Your Treatment Plan" card — shows plan status, last updated
     Click → navigates to PlanView
   - "Your Homework" quick view — shows count of incomplete items
     Click → navigates to Homework
   - "Recent Sessions" — last 2-3 sessions with client_summary preview

2. frontend/src/pages/client/PlanView.tsx
   - Fetch GET /api/my/treatment-plan
   - If no approved plan yet: friendly empty state
     "Your therapist hasn't shared a plan yet. Check back after your next session!"
   - Plan sections (client-friendly names and styling):
     - "What We're Working On" (presenting concerns)
     - "Your Goals" (short-term + long-term, visually distinct)
     - "Our Approach" (interventions in plain language)
     - "Things to Try Before Next Session" (homework)
     - "Your Strengths" (empowering language)
   - NO risk indicators, NO clinical impressions, NO citations
   - "Last updated" timestamp at bottom
   - Warm, spacious layout: teal/green accents, rounded cards, generous padding

3. frontend/src/pages/client/Sessions.tsx
   - Fetch GET /api/my/sessions
   - List of sessions with client-friendly summaries
   - Each session card shows:
     - Session date
     - "Here's what we worked on together..." summary
     - Key themes as soft badges

4. frontend/src/pages/client/Homework.tsx
   - Fetch GET /api/my/homework
   - Checklist layout
   - Each item: checkbox + description
   - Check → PATCH /api/homework/{id} with completed: true
   - Visual feedback on completion (checkmark animation or green highlight)
   - Progress indicator: "3 of 5 completed"
   - Encouraging message when all done: "Great work this week!"

Create supporting components in frontend/src/components/client/:
- WelcomeCard.tsx
- PlanSectionClient.tsx (warm styling, rounded corners, teal accents)
- HomeworkChecklist.tsx
- HomeworkItem.tsx
- SessionSummaryClient.tsx

Import ALL types from frontend/src/types/index.ts.
Style: Warm, spacious, wellness-app feel. Teal/green accents, soft shadows,
rounded corners, generous whitespace. Think health app, NOT clinical tool.
Use emoji sparingly and only for encouraging feedback (e.g., checkmark on homework).
```

---

### Step 2.1Q — QA Agent: Verify Day 2 Agent Output

**Spawn after Agents E and F complete (before integration).**

#### Agent QA-2: Day 2 Quality Gate

**Prompt:**
```
You are a QA reviewer for the frontend of a mental health treatment plan
application. Verify that Agents E and F produced code matching the spec.
Do NOT fix anything — just report pass/fail.

Read every file listed below and check the criteria.

## Agent E — Therapist Pages
Files to check:
- frontend/src/pages/therapist/Dashboard.tsx
- frontend/src/pages/therapist/ClientDetail.tsx
- frontend/src/pages/therapist/NewSession.tsx
- frontend/src/pages/therapist/PlanReview.tsx
- frontend/src/pages/therapist/Evaluation.tsx
- frontend/src/components/therapist/ClientCard.tsx
- frontend/src/components/therapist/TranscriptUpload.tsx
- frontend/src/components/therapist/GenerationProgress.tsx
- frontend/src/components/therapist/PlanSection.tsx
- frontend/src/components/therapist/CitationSidebar.tsx
- frontend/src/components/therapist/SafetyFlagBanner.tsx
- frontend/src/components/therapist/SessionSummaryCard.tsx

Checks:
- [ ] All 12 files above exist
- [ ] All types imported from frontend/src/types/index.ts (no locally redefined
      interfaces that duplicate shared types)
- [ ] App.tsx was NOT modified by this agent
- [ ] Dashboard.tsx fetches GET /api/clients
- [ ] Dashboard.tsx shows client cards with name, session count, safety flag badge
- [ ] Dashboard.tsx has "Add Client" with inline form
- [ ] ClientDetail.tsx fetches GET /api/clients/{id}
- [ ] ClientDetail.tsx shows session history table and plan summary card
- [ ] NewSession.tsx has TranscriptUpload with "Paste" and "Upload" tabs
- [ ] NewSession.tsx POSTs to /api/clients/{id}/sessions then
      /api/sessions/{id}/generate
- [ ] GenerationProgress.tsx consumes the streamed POST response and shows 4 stages
- [ ] GenerationProgress.tsx handles "complete" event (navigate) and "error"
      event (retry button)
- [ ] PlanReview.tsx fetches GET /api/clients/{id}/treatment-plan
- [ ] PlanReview.tsx renders SafetyFlagBanner at top when flags exist
- [ ] PlanReview.tsx renders all plan sections: Presenting Concerns, Clinical
      Impressions, Short-Term Goals, Long-Term Goals, Interventions, Homework,
      Strengths, Risk Indicators
- [ ] PlanSection.tsx has "Show Citations" button opening CitationSidebar
- [ ] PlanSection.tsx has "Edit" button toggling to textarea mode
- [ ] PlanSection.tsx Save action POSTs to /api/treatment-plans/{id}/edit and
      refreshes the plan
- [ ] CitationSidebar.tsx uses shadcn Sheet component
- [ ] SafetyFlagBanner.tsx shows acknowledge button per flag
- [ ] PlanReview.tsx has "Approve & Share" button disabled when unacknowledged
      flags exist
- [ ] Evaluation.tsx is a placeholder (not yet implemented)
- [ ] All data fetching uses TanStack React Query (useQuery/useMutation)
- [ ] All HTTP calls go through frontend/src/api/client.ts

## Agent F — Client Pages
Files to check:
- frontend/src/pages/client/Dashboard.tsx
- frontend/src/pages/client/PlanView.tsx
- frontend/src/pages/client/Sessions.tsx
- frontend/src/pages/client/Homework.tsx
- frontend/src/components/client/WelcomeCard.tsx
- frontend/src/components/client/PlanSectionClient.tsx
- frontend/src/components/client/HomeworkChecklist.tsx
- frontend/src/components/client/HomeworkItem.tsx
- frontend/src/components/client/SessionSummaryClient.tsx

Checks:
- [ ] All 9 files above exist
- [ ] All types imported from frontend/src/types/index.ts (no locally redefined
      interfaces)
- [ ] App.tsx was NOT modified by this agent
- [ ] Dashboard.tsx shows welcome message with client name and current date
- [ ] Dashboard.tsx has privacy disclaimer card
- [ ] Dashboard.tsx has plan card, homework quick view, recent sessions
- [ ] PlanView.tsx fetches GET /api/my/treatment-plan
- [ ] PlanView.tsx shows friendly empty state when no approved plan
- [ ] PlanView.tsx renders sections with client-friendly names: "What We're
      Working On", "Your Goals", "Our Approach", "Things to Try", "Your Strengths"
- [ ] PlanView.tsx does NOT display: risk indicators, clinical impressions,
      citations, clinical jargon
- [ ] Sessions.tsx fetches GET /api/my/sessions
- [ ] Sessions.tsx shows client-friendly summaries with key themes as badges
- [ ] Homework.tsx fetches GET /api/my/homework
- [ ] Homework.tsx has checkbox per item → PATCH /api/homework/{id}
- [ ] Homework.tsx shows progress indicator ("X of Y completed")
- [ ] Homework.tsx shows encouraging message when all complete
- [ ] All data fetching uses TanStack React Query
- [ ] Client pages use warm styling (teal/green accents, rounded corners,
      generous padding) — visually distinct from therapist pages

## Cross-Agent Consistency
- [ ] No duplicate component names between therapist/ and client/ directories
- [ ] Both agents use the same API client (frontend/src/api/client.ts)
- [ ] Both agents use the same auth context (frontend/src/context/AuthContext.tsx)
- [ ] Route paths used in navigate() calls match routes defined in App.tsx

Report format:
For each check, output ✅ PASS or ❌ FAIL with a one-line explanation for
failures. At the end, output a summary: total checks, passed, failed, and a
list of blocking issues that must be fixed before integration.
```

---

### Step 2.2 — Orchestrator: Integration

After QA-2 passes (fix any blocking issues first), then proceed.
After both agents complete:

1. **Verify no conflicts**: Check App.tsx routes are correct, no duplicate components
2. **Fix import issues**: Ensure all component imports resolve
3. **Start both servers**:
   ```bash
   # Terminal 1
   cd backend && uvicorn app.main:app --reload --port 8000
   # Terminal 2
   cd frontend && npm run dev
   ```
4. **Walk through full flow in browser** (see manual testing below)

---

### DAY 2 CHECKPOINT — Manual Testing

**Open browser to http://localhost:5173**

#### 1. Login Flow
```
- Go to /login
- Enter: therapist@tava.health / demo123
- Should redirect to /therapist/dashboard
- Sidebar should show: Dashboard, Clients, Evaluation
- Privacy disclaimer footer visible
```

#### 2. Therapist Dashboard
```
- Should show at least 1 client (from seed data)
- Client card shows name and session count
- "Add Client" creates a new client inline
- Click a client card → navigates to client detail
```

#### 3. Client Detail Page
```
- Shows client name
- Session history (at least 1 from Day 1 testing)
- "New Session" button visible
- Treatment plan card shows current plan status
```

#### 4. New Session Flow (THE KEY DEMO FLOW)
```
- Click "New Session"
- Paste a transcript into the text area:
  """
  Therapist: How have you been since our last session?
  Client: It's been a rough week. I keep having these panic attacks at work.
  Therapist: Tell me about what happens during these episodes.
  Client: My heart starts racing, I can't breathe, and I feel like I'm going to die. It happened three times this week.
  Therapist: That sounds really frightening. Have you noticed any patterns in when they occur?
  Client: Usually before big meetings. I've started avoiding them, which is causing problems with my boss.
  Therapist: It sounds like the avoidance is creating additional stress. I'd like us to try some cognitive behavioral techniques.
  Client: I'm willing to try anything at this point.
  Therapist: Let's start with identifying the automatic thoughts that come up before these meetings.
  Client: Like what kind of thoughts?
  Therapist: The ones that might be telling you something catastrophic is going to happen.
  Client: Oh, definitely. I always think I'm going to embarrass myself or that everyone will see I'm incompetent.
  Therapist: Those are great examples of catastrophic thinking. We can work on challenging those.
  """
- Set date and duration
- Click "Generate Treatment Plan"
- Generation progress overlay should appear
- Should see stages updating via SSE
- On complete: should navigate to plan review
```

#### 5. Plan Review Page
```
- Treatment plan displays with all sections
- Each section has content with clinical language
- Citation icons (🔗) visible on each section
- Click citation → sidebar opens showing transcript excerpts with line numbers
- Click "Edit" on a section, change content, save, and verify the refreshed plan
  shows the update while remaining in draft state
- "Approve & Share with Client" button visible
- Click Approve
```

#### 6. Client Login & Dashboard
```
- Logout therapist
- Login as: client@tava.health / demo123
- Should redirect to /client/dashboard
- Welcome message with client name
- "Your Treatment Plan" card visible
- Click → see plan in plain language
- Verify: NO clinical jargon, NO risk indicators, NO citations
- Verify: warm, spacious styling (different from therapist view)
```

#### 7. Client Homework
```
- Navigate to Homework page
- Should see homework items from treatment plan
- Click checkbox to complete an item
- Verify checkbox state persists after page refresh
```

#### 8. Safety Flags (if crisis session exists from Day 1)
```
- Login as therapist
- Go to the client who has the crisis session
- Plan review should show safety flag banner at top
- Red/amber alert with transcript excerpt
- "Acknowledge" button on each flag
- "Approve" button should be disabled until all flags acknowledged
- Acknowledge all flags → Approve button enables
```

#### Day 2 Pass Criteria
- [ ] Login works for both roles with correct redirects
- [ ] Therapist dashboard shows clients
- [ ] Transcript paste → generate → plan review flow works end-to-end
- [ ] Plan shows structured sections with citations
- [ ] Citation sidebar opens and shows transcript excerpts
- [ ] Therapist can edit and save plan sections before approval
- [ ] Plan approval works
- [ ] Client sees approved plan in plain language
- [ ] Client view has NO clinical content (jargon, risk, citations)
- [ ] Client can complete homework items
- [ ] Safety flags display correctly on therapist view
- [ ] Privacy disclaimer footer on all pages
- [ ] Two visually distinct UIs (therapist: professional/dense, client: warm/spacious)

---

## DAY 3: Lifecycle + Evaluation + Polish

### Goal
Recommended/stretch work layered on top of the Day 2 core flow: plan versioning,
evaluation dashboard, tests, documentation, final polish.

---

### Step 3.0 — Spawn TWO implementation agents in parallel

#### Agent G: Plan Versioning + Diff

**Prompt:**
```
You are adding treatment plan versioning and diff viewing to an existing
mental health treatment plan application.

IMPORTANT: Read the following files CAREFULLY before making changes. You are
modifying existing code written by other developers. Understand the existing
component structure, props, state management, and imports before editing.

Read FIRST:
- backend/app/models/treatment_plan.py and treatment_plan_version.py
- backend/app/routes/treatment_plans.py (read the existing route implementations)
- backend/app/routes/generate.py (read how generation currently works)
- backend/app/services/ai_pipeline.py (understand the pipeline interface)
- frontend/src/pages/therapist/PlanReview.tsx (understand existing structure, props, state)
- frontend/src/components/therapist/PlanSection.tsx (understand existing component API)
- frontend/src/types/index.ts (use existing TypeScript types)

Backend tasks:

1. backend/app/services/plan_service.py
   - get_version_history(plan_id) -> list of version summaries (id, version_number, source, session_id, change_summary, created_at)
   - compute_diff(version_a_id, version_b_id) -> DiffResponse
     Use Python difflib to compare therapist_content sections
     Return per-section: status (unchanged|modified|added|removed), old text, new text

2. Ensure these routes work in backend/app/routes/treatment_plans.py:
   - GET /api/treatment-plans/{plan_id}/versions — returns version list
   - GET /api/treatment-plans/{plan_id}/diff?v1=X&v2=Y — returns structured diff
   - POST /api/treatment-plans/{plan_id}/edit — creates new version from therapist edit
   Read the existing file first. If these routes already have stub implementations
   from Agent C, fill them in. If they're missing, add them.

3. Verify the generate route (backend/app/routes/generate.py) handles plan updates:
   - When generating for a client that already has a plan, existing plan should be
     passed to AI pipeline. Read generate.py — if this is already implemented, skip.
     If not, add the logic: fetch current version's therapist_content, pass as
     existing_plan to run_pipeline(), create version with source "ai_updated",
     revert plan status to "draft".

Frontend tasks:

4. frontend/src/components/therapist/VersionHistory.tsx
   - Timeline of versions (vertical list)
   - Each entry: version number, source badge (AI Generated / Therapist Edited / AI Updated), date, change summary
   - Select two versions for comparison
   - "Compare" button
   - Import types from frontend/src/types/index.ts

5. frontend/src/components/therapist/VersionDiff.tsx
   - Install react-diff-viewer-continued (npm install react-diff-viewer-continued)
   - Side-by-side or inline diff view per section
   - Green highlights for additions, red for removals
   - Section headers

6. Add a "Version History" tab to PlanReview.tsx
   - READ PlanReview.tsx first to understand its current structure
   - Add Tabs component (from shadcn): "Current Plan" | "Version History"
   - Wrap existing plan content in the "Current Plan" tab
   - Version History tab shows VersionHistory + VersionDiff components
   - Preserve ALL existing functionality — do not break citations, safety flags, approve flow

7. Enhance inline edit functionality in PlanSection.tsx:
   - READ PlanSection.tsx first to understand its current props and structure
   - If "Edit" functionality already exists (from Agent E), verify it works
   - If not: add "Edit" button that toggles section to textarea
   - Save → POST /api/treatment-plans/{id}/edit with updated content
   - Creates new version, refreshes plan view
   - Cancel → reverts to display mode
```

#### Agent H: Evaluation Framework

**Prompt:**
```
You are building an AI evaluation framework for a mental health treatment plan
application. The framework validates AI output quality and measures readability.

Read:
- backend/app/schemas/evaluation.py
- backend/app/services/ai_pipeline.py
- backend/evaluation/fixtures/ (synthetic transcripts)

Backend tasks:

1. backend/app/utils/readability.py
   - Uses textstat library
   - compute_readability(text: str) -> ReadabilityScores
     Returns: flesch_reading_ease, flesch_kincaid_grade, gunning_fog,
     avg_sentence_length, avg_word_length

2. backend/app/services/evaluation_service.py
   - validate_plan_structure(therapist_content, client_content, transcript_lines) -> StructuralValidationResult
     Checks: schema compliance, required sections non-empty, citation bounds valid,
     citation text fuzzy matches transcript, client view has no clinical jargon
     (check for: ICD, DSM, F41, F32, ideation, contraindicated, etiology, comorbid,
      maladaptive, psychopharmacol, differential diagnosis),
     client view has no risk data
   - analyze_readability(therapist_content, client_content) -> ReadabilityResult
     Extracts all text from both plans, runs readability scoring,
     checks client plan <= 8th grade Flesch-Kincaid,
     checks therapist score > client score + 2 grade levels
   - check_safety_detection(safety_flags, transcript_name, expected_flags_config) -> SafetyDetectionResult
     Compares detected flags against expected flags for known fixture transcripts
   - async run_evaluation(fixture_dir: str) -> EvaluationRunResponse
     For each transcript fixture:
       Run AI pipeline
       Run structural validation
       Run readability analysis
       Run safety detection check (for crisis.txt and substance.txt)
       Record generation time and token usage
     Aggregate results

3. backend/app/routes/evaluation.py
   - POST /api/evaluation/run — triggers evaluation, returns SSE stream
     Stream results per transcript as they complete
   - GET /api/evaluation/results — returns past evaluation runs
   - Store results in a simple evaluation_runs table (id, run_at, results JSONB)
     Create the SQLAlchemy model and Alembic migration for this

4. Expected safety flags config:
   - anxiety.txt: 0 flags
   - depression.txt: 0 flags
   - crisis.txt: >= 1 flag (suicidal_ideation or severe_distress)
   - substance.txt: >= 1 flag (substance_crisis)
   - relationship.txt: 0 flags

Frontend tasks:

5. frontend/src/pages/therapist/Evaluation.tsx (replace placeholder)
   - "Run Evaluation" button → POST /api/evaluation/run (streamed response)
   - Consume the streamed POST response via the shared `frontend/src/lib/sse.ts`
     helper rather than `EventSource`
   - Shows progress as each transcript completes
   - Results display:
     a. Structural Validation table:
        Transcript | Schema | Citations | No Jargon | No Risk Data | Pass
     b. Readability Analysis table:
        Transcript | Therapist Grade | Client Grade | Client ≤ 8th | Separation
     c. Safety Detection table:
        Transcript | Expected Flags | Detected | Pass
   - Show aggregate stats: overall pass rates, average grade levels
   - If past results exist (GET /api/evaluation/results), show most recent by default
   - Use shadcn Table component for display
```

**Dependency correction:** Spawn Agent I only after Agents G and H complete.
Its tests and README depend on the final versioning and evaluation surfaces,
so running it in parallel with those agents creates stale docs/tests risk.

#### Agent I: Tests + Documentation

**Prompt:**
```
You are writing tests and documentation for a mental health treatment plan
application.

Read the codebase structure, especially:
- backend/app/services/ai_pipeline.py
- backend/app/utils/safety_patterns.py
- backend/app/utils/readability.py
- backend/app/services/evaluation_service.py
- backend/app/schemas/treatment_plan.py

Create the following test files:

1. backend/tests/test_ai_output_parsing.py
   - Test that valid therapist plan JSON parses into TherapistPlanContent Pydantic model
   - Test that valid client plan JSON parses into ClientPlanContent Pydantic model
   - Test that malformed JSON (missing required fields) raises ValidationError
   - Test that JSON with extra fields is handled gracefully (ignored or accepted)
   - Test with a realistic AI output fixture (hardcode a sample response)

2. backend/tests/test_safety_detection.py
   - Test that "I want to kill myself" triggers suicidal_ideation flag
   - Test that "I've been cutting myself" triggers self_harm flag
   - Test that "I want to hurt him" triggers harm_to_others flag
   - Test that "I blacked out from drinking" triggers substance_crisis flag
   - Test that "I'm angry at my husband" does NOT trigger any flag (false positive resistance)
   - Test that "I used to self-harm but stopped years ago" triggers a flag (it should — historical mentions still need therapist awareness)
   - Test deduplication: if AI already flagged a line, regex doesn't create duplicate

3. backend/tests/test_plan_validation.py
   - Test citation bounds: valid line numbers pass, out-of-bounds fail
   - Test client jargon check: plan with "F41.1" fails, plan without jargon passes
   - Test client risk check: plan mentioning "suicidal" fails

4. backend/tests/test_readability.py
   - Test that clinical text scores higher grade level than plain text
   - Test with known text samples that have established Flesch-Kincaid scores
   - Test the threshold check: text at 8th grade passes, text at 12th grade fails

5. backend/tests/conftest.py
   - Shared fixtures: sample therapist_content dict, sample client_content dict,
     sample transcript lines

Make tests runnable with: cd backend && pytest tests/ -v

Then create documentation:

6. README.md (project root)
   Structure:
   - Project title and one-line description
   - Tech stack overview (table)
   - Architecture diagram (ASCII)
   - Quick start:
     Prerequisites (Python 3.11+, Node 18+, Docker)
     docker-compose up -d
     Backend setup (pip install, alembic upgrade, seed, uvicorn)
     Frontend setup (npm install, npm run dev)
     Demo accounts (therapist@tava.health / client@tava.health, password: demo123)
   - AI System Design:
     Two-stage pipeline explanation
     Prompt strategy (clinical accuracy, citation-based explainability)
     Model choice rationale (Claude Sonnet for nuance + 200k context)
     Structured output approach
     Safety detection (3 layers)
   - Key Product Decisions:
     Why dual views (therapist vs client)
     Why therapist approval gate
     Why version immutability
     Why citation-based explainability as the bonus feature
   - Evaluation Framework:
     What it measures (structural validity, readability, safety detection)
     How to run it
   - Limitations and Future Ideas:
     No real audio/video processing (future: Whisper integration)
     No real-time collaboration
     No therapist preference learning (future: few-shot library)
     No multi-language support
     Auth is demo-grade (future: OAuth, session management)
   - Testing:
     How to run tests
     What's covered
```

---

### Step 3.0Q — QA Agent: Verify Day 3 Agent Output

**Spawn after Agents G, H, and I complete (before integration).**

#### Agent QA-3: Day 3 Quality Gate

**Prompt:**
```
You are a QA reviewer for a mental health treatment plan application. Verify
that Agents G, H, and I produced code matching the spec. Do NOT fix anything —
just report pass/fail.

Read every file listed below and check the criteria.

## Agent G — Plan Versioning + Diff
Files to check:
- backend/app/services/plan_service.py
- backend/app/routes/treatment_plans.py (check for new/updated route logic)
- backend/app/routes/generate.py (check plan update handling)
- frontend/src/components/therapist/VersionHistory.tsx
- frontend/src/components/therapist/VersionDiff.tsx
- frontend/src/pages/therapist/PlanReview.tsx (check for Version History tab)
- frontend/src/components/therapist/PlanSection.tsx (check for edit functionality)

Checks:
- [ ] plan_service.py exists with get_version_history() and compute_diff()
- [ ] compute_diff() uses Python difflib and returns per-section diffs with
      status (unchanged|modified|added|removed)
- [ ] treatment_plans.py has working GET .../versions route
- [ ] treatment_plans.py has working GET .../diff?v1=X&v2=Y route
- [ ] treatment_plans.py has working POST .../edit route that creates a new
      version (not modifying existing)
- [ ] generate.py handles plan updates: when client already has a plan, passes
      existing plan to run_pipeline, creates version with source "ai_updated",
      reverts plan status to "draft"
- [ ] VersionHistory.tsx displays timeline of versions with: version number,
      source badge, date, change summary
- [ ] VersionHistory.tsx allows selecting two versions for comparison
- [ ] VersionDiff.tsx shows side-by-side or inline diff with green/red highlights
- [ ] PlanReview.tsx has Tabs: "Current Plan" and "Version History"
- [ ] PlanReview.tsx preserves ALL existing functionality (citations, safety
      flags, approve flow) — verify existing code was not deleted or broken
- [ ] PlanSection.tsx has working Edit button → textarea → Save/Cancel
- [ ] Save action POSTs to /api/treatment-plans/{id}/edit
- [ ] Types imported from frontend/src/types/index.ts (no local duplicates)

## Agent H — Evaluation Framework
Files to check:
- backend/app/utils/readability.py
- backend/app/services/evaluation_service.py
- backend/app/routes/evaluation.py
- backend/app/models/ (check for evaluation_runs model)
- alembic/versions/ (check for new migration)
- frontend/src/pages/therapist/Evaluation.tsx (should replace placeholder)

Checks:
- [ ] readability.py uses textstat library
- [ ] readability.py returns: flesch_reading_ease, flesch_kincaid_grade,
      gunning_fog, avg_sentence_length, avg_word_length
- [ ] evaluation_service.py has validate_plan_structure() checking: schema
      compliance, non-empty sections, citation bounds, citation text fuzzy
      match, clinical jargon absence in client view, no risk data in client view
- [ ] evaluation_service.py has analyze_readability() checking: client plan
      <= 8th grade, therapist > client + 2 grades
- [ ] evaluation_service.py has check_safety_detection() comparing detected
      vs expected flags
- [ ] evaluation_service.py has run_evaluation() that processes all fixtures
- [ ] evaluation.py has POST /api/evaluation/run returning SSE stream
- [ ] evaluation.py has GET /api/evaluation/results
- [ ] An evaluation_runs SQLAlchemy model exists (id, run_at, results JSONB)
- [ ] A new Alembic migration exists for the evaluation_runs table
- [ ] Evaluation.tsx replaces the placeholder (not just "Coming in Day 3")
- [ ] Evaluation.tsx has "Run Evaluation" button connecting to SSE endpoint
- [ ] Evaluation.tsx displays 3 result tables: Structural Validation,
      Readability Analysis, Safety Detection
- [ ] Expected safety config: anxiety=0, depression=0, crisis>=1, substance>=1,
      relationship=0

## Agent I — Tests + Documentation
Files to check:
- backend/tests/conftest.py
- backend/tests/test_ai_output_parsing.py
- backend/tests/test_safety_detection.py
- backend/tests/test_plan_validation.py
- backend/tests/test_readability.py
- README.md (project root)

Checks:
- [ ] conftest.py has shared fixtures: sample therapist_content, sample
      client_content, sample transcript lines
- [ ] test_ai_output_parsing.py tests: valid parse to TherapistPlanContent,
      valid parse to ClientPlanContent, malformed JSON raises ValidationError,
      extra fields handled gracefully (4+ tests)
- [ ] test_safety_detection.py tests: suicidal_ideation trigger, self_harm
      trigger, harm_to_others trigger, substance_crisis trigger, false positive
      resistance ("angry at husband"), historical mention detection,
      deduplication (6+ tests)
- [ ] test_plan_validation.py tests: valid/invalid citation bounds, jargon
      detection ("F41.1"), risk data detection ("suicidal") (3+ tests)
- [ ] test_readability.py tests: clinical > plain grade level, known FK scores,
      threshold check (3+ tests)
- [ ] All tests runnable with: cd backend && pytest tests/ -v
- [ ] README.md exists at project root
- [ ] README.md contains: project title, tech stack table, architecture diagram,
      quick start with prerequisites, demo accounts (therapist@tava.health /
      client@tava.health / demo123), AI system design section, key product
      decisions, evaluation framework section, limitations, testing section
- [ ] README.md quick start instructions reference docker-compose, pip install,
      alembic upgrade, seed, uvicorn, npm install, npm run dev

## Cross-Agent Consistency
- [ ] Agent G did not break existing PlanReview.tsx functionality (citations,
      safety flags, approve flow still present)
- [ ] Agent G did not break existing PlanSection.tsx props/API
- [ ] Agent H's evaluation model does not conflict with existing models
- [ ] Agent I's tests import from the correct module paths
- [ ] No duplicate route registrations in main.py

Report format:
For each check, output ✅ PASS or ❌ FAIL with a one-line explanation for
failures. At the end, output a summary: total checks, passed, failed, and a
list of blocking issues that must be fixed before integration.
```

---

### Step 3.1 — Orchestrator: Integration + Seed Enhancement

After QA-3 passes (fix any blocking issues first), then proceed.
After all three agents complete:

1. **Run migrations** (if evaluation added a new table):
   ```bash
   cd backend && alembic upgrade head
   ```
   Agent H should have already created the migration file. Do not create a
   second revision during integration unless the schema changed again.

2. **Run tests**:
   ```bash
   cd backend && pytest tests/ -v
   ```
   Fix any failures.

3. **Enhance seed data** — Do this yourself or spawn a small agent:
   - Pre-generate treatment plans for 2-3 clients (so demo isn't empty)
   - Include multiple plan versions (to demonstrate versioning)
   - Pre-seed one evaluation run result (so evaluation dashboard has data)
   - Add a second client with 2 sessions to demonstrate plan updates

4. **Frontend integration fixes**:
   - Verify version history tab works on PlanReview
   - Verify evaluation page loads and displays results
   - Verify all routes are registered in App.tsx

5. **Polish pass**:
   - Check all empty states render correctly
   - Check loading states (skeletons or spinners)
   - Check error states (API failures show user-friendly messages)
   - Verify mobile responsiveness on client pages (resize browser to 375px width)

---

### DAY 3 CHECKPOINT — Manual Testing

#### 1. Plan Versioning
```
- Login as therapist
- Go to a client with an existing plan
- Plan Review page → "Version History" tab
- Should show at least 1 version (from initial generation)
- Create a new version by editing a section:
  - Click "Edit" on Presenting Concerns
  - Modify the text
  - Click "Save"
  - Version History should now show 2 versions
  - Source of new version: "Therapist Edited"
```

#### 2. Plan Update from New Session
```
- Same client, click "New Session" from client detail
- Paste a different transcript (e.g., follow-up session discussing progress)
- Generate treatment plan
- Should create a new version (not a new plan)
- Version History should show the update with source "AI Updated"
- Change summary should explain what changed
- Plan status should revert to "draft"
```

#### 3. Version Diff
```
- In Version History, select version 1 and version 3 (or latest)
- Click "Compare"
- Should see side-by-side diff
- Added text in green, removed text in red
- Each section compared independently
```

#### 4. Inline Plan Editing
```
- Go to Current Plan tab
- Click Edit on any section
- Section becomes a textarea
- Modify content, click Save
- New version created
- Click Cancel on another section — reverts without saving
```

#### 5. Evaluation Dashboard
```
- Navigate to /therapist/evaluation
- If pre-seeded: should show most recent evaluation results
  - Structural validation table with pass/fail per transcript
  - Readability table with grade levels
  - Safety detection table
- Click "Run Evaluation" (warning: this makes ~10 API calls, takes 2-4 min)
  - Progress should stream per transcript
  - Results should populate incrementally
- Verify:
  - Client plans have lower grade level than therapist plans
  - Crisis transcript has safety flags detected
  - Relationship transcript has 0 flags (no false positive)
```

#### 6. Tests
```bash
cd backend && pytest tests/ -v
# Expected: All tests pass
# Specifically verify:
#   test_ai_output_parsing — 4+ tests pass
#   test_safety_detection — 6+ tests pass
#   test_plan_validation — 3+ tests pass
#   test_readability — 3+ tests pass
```

#### 7. Documentation
```
- Open README.md
- Verify it contains:
  - Setup instructions that actually work
  - Architecture overview
  - AI system design section
  - Demo account credentials
  - How to run tests
```

#### 8. Full End-to-End Regression
```
Run through the complete flow one more time:
1. Login as therapist
2. Create a new client
3. Create a session with a pasted transcript
4. Generate treatment plan → watch progress
5. Review plan with citations
6. Edit a section
7. Approve the plan
8. Logout → login as client
9. View the plan (warm, plain language)
10. Complete a homework item
11. Logout → login as therapist
12. Verify homework completion visible on therapist side
```

#### Day 3 Pass Criteria
- [ ] Plan editing creates new versions
- [ ] Plan update from new session works (new version, draft status)
- [ ] Version history displays correctly with timeline
- [ ] Version diff shows additions/removals per section
- [ ] Evaluation dashboard shows structural + readability + safety results
- [ ] All tests pass
- [ ] README has complete setup instructions and AI design writeup
- [ ] Full end-to-end flow works without errors
- [ ] Mobile-friendly client pages (check at 375px width)
- [ ] Pre-seeded data makes demo immediately explorable

---

## Agent Dependency Map

```
DAY 1:
  Step 1.0 (Orchestrator: scaffolding + schemas + auth_service + base model + contracts)
      │
      ├──→ Agent A (DB models + seed)     ──── MUST COMPLETE FIRST
      │         │
      │         └──→ Agent D (Transcripts — background, no code deps)
      │
      │    (after Agent A completes)
      │         │
      │         ├──→ Agent B (AI pipeline)       ──┐
      │         └──→ Agent C (Routes — uses models)──┼──→ QA-1 (verify all agents)
      │                                              │         │
      │                                              │    (fix blocking issues)
      │                                              │         │
      │                                              │         └──→ Step 1.3 (Integration)
      │                                              │                   │
      │                                              │                   └──→ Manual Testing
      │                                              │
      └──→ Agent D may still be running — check fixtures exist

DAY 2:
  Step 2.0 (Orchestrator: frontend scaffolding + types + ALL routes in App.tsx)
      │
      ├──→ Agent E (Therapist pages — does NOT touch App.tsx)  ──┐
      └──→ Agent F (Client pages — does NOT touch App.tsx)     ──┼──→ QA-2 (verify agents E+F)
                                                                  │         │
                                                                  │    (fix blocking issues)
                                                                  │         │
                                                                  │         └──→ Step 2.2 (Integration)
                                                                  │                   │
                                                                  │                   └──→ Manual Testing

DAY 3:
      ├──→ Agent G (Versioning + diff — READS existing components first)  ──┐
      └──→ Agent H (Evaluation)                                            ──┼──→ Agent I (Tests + docs)
                                                                             │         │
                                                                             │    (after G+H complete)
                                                                             │         │
                                                                             └─────────┼──→ QA-3 (verify agents G+H+I)
                                                                                       │
                                                                                  (fix blocking issues)
                                                                                        │
                                                                                        └──→ Step 3.1 (Integration + seed)
                                                                                                  │
                                                                                                  └──→ Manual Testing
```

## Key Dependency Insights

1. **Agent A is the critical path on Day 1.** Models must exist before routes (Agent C)
   can query them. The old plan ran A/B/C in parallel, but C would blindly guess
   model field names. Now A runs first, then B+C run in parallel with models as a
   known quantity.

2. **Agent D (transcripts) has zero code dependencies.** It only creates .txt files.
   Run it in background from the start — it can finish whenever.

3. **The orchestrator creates more on Day 1 than before** (auth_service, base model,
   model field contracts, PipelineResult schema, a seed transcript). This front-loads
   ~30 min of work but eliminates the top 3 integration risks.

4. **On Day 2, App.tsx is a no-touch zone for agents.** The orchestrator defines all
   routes, boot-safe placeholders, and all shared TypeScript types. Agents E and F
   only create files — they never modify shared files. This eliminates merge conflicts
   without breaking the dev server before page files exist.

5. **On Day 3, Agent G must read before writing.** It modifies PlanReview.tsx and
   PlanSection.tsx which were created by Agent E. The prompt explicitly requires
   reading these files first and preserving existing functionality.

6. **Agent I is not safely parallel with Agents G and H.** Its test suite and README
   need the final versioning and evaluation interfaces, so it should start only after
   those implementation agents finish.

7. **QA agents are the safety net between build and integration.** Each QA agent
   (QA-1, QA-2, QA-3) runs after its day's build agents complete but before
   integration. They catch spec violations, missing files, wrong imports, and
   cross-agent inconsistencies — issues that are cheap to fix before integration
   but expensive to debug after. QA agents are read-only: they report but never
   fix, so the orchestrator retains control over remediation.

## Parallel Speedup Estimate

| Phase | Sequential | Parallel | Savings |
|---|---|---|---|
| Day 1 Step 1.0 (orchestrator) | ~2h | ~2h (must be sequential) | 0h |
| Day 1 Agent A (must be first) | ~1.5h | ~1.5h (sequential) | 0h |
| Day 1 Agents B+C+D | ~5h | ~2.5h (B+C parallel, D background) | ~2.5h |
| Day 1 QA-1 | ~0.5h | ~0.5h (sequential gate) | 0h |
| Day 2 agents (E+F) | ~4h | ~2.5h (bottleneck: Agent E) | ~1.5h |
| Day 2 QA-2 | ~0.5h | ~0.5h (sequential gate) | 0h |
| Day 3 agents (G+H+I) | ~5h | ~2h (bottleneck: Agent H) | ~3h |
| Day 3 QA-3 | ~0.5h | ~0.5h (sequential gate) | 0h |
| **Total agent work** | **~19h** | **~12h** | **~7h** |

Integration and manual testing add ~1.5h per day. QA agents add ~0.5h per day
but reduce integration debugging by an estimated ~1h per day (net savings).
Each "day" is achievable in a focused ~5-6 hour session. The Day 1 parallelism
is reduced compared to v1 (because Agent A must run first), but the tradeoff is
dramatically lower integration risk — the #1 time sink in parallel agent builds.
