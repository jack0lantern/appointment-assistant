# Tava Health — AI Treatment Plan Assistant

AI-powered mental health treatment plan generation. Therapists upload session transcripts; the system generates structured, evidence-based treatment plans with citations, a client-friendly view, and safety flag detection.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Database | PostgreSQL (JSONB for plan content) |
| ORM | SQLAlchemy 2.0 (async) + Alembic |
| Backend | Python 3.11+ + FastAPI (async) |
| AI Provider | Anthropic Claude Sonnet 4.6 |
| AI Integration | Anthropic SDK (direct, no framework) |
| Frontend | React 18 + Vite + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui |
| Auth | JWT (demo-grade) |
| Evaluation | textstat (readability) + Pydantic (structural) |

---

## Architecture

```
┌─────────────────────┐         ┌──────────────────────────────┐
│   Therapist Browser │◄───────►│  React + Vite Frontend       │
│   Client Browser    │         │  (port 5173)                 │
└─────────────────────┘         └──────────────┬───────────────┘
                                               │ HTTP / SSE
                                ┌──────────────▼───────────────┐
                                │  FastAPI Backend              │
                                │  (port 8000)                  │
                                │                               │
                                │  ┌───────────────────────┐   │
                                │  │  AI Pipeline Service   │   │
                                │  │  1. Preprocess         │   │
                                │  │  2. Therapist Plan     │◄──┼──► Claude Sonnet 4.6
                                │  │  3. Client View        │   │
                                │  │  4. Safety Scan        │   │
                                │  └───────────────────────┘   │
                                │                               │
                                └──────────────┬───────────────┘
                                               │
                                ┌──────────────▼───────────────┐
                                │  PostgreSQL (port 5433)       │
                                │  JSONB for plan content       │
                                └──────────────────────────────┘
```

---

## Quick Start

### Prerequisites
- Python 3.11+
- Node 18+
- Docker + Docker Compose

### 1. Start PostgreSQL
```bash
docker-compose up -d
```

### 2. Backend Setup
```bash
cd backend
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Copy and configure environment
cp .env.example .env
# Edit .env — set ANTHROPIC_API_KEY to your key

# Run migrations
alembic upgrade head

# Seed demo data
python -m app.seed

# Start server
uvicorn app.main:app --reload --port 8000
```

### 3. Frontend Setup
```bash
cd frontend
npm install
npm run dev
# Opens at http://localhost:5173
```

### Demo Accounts

| Role | Email | Password |
|------|-------|----------|
| Therapist | therapist@tava.health | demo123 |
| Client | client@tava.health | demo123 |

---

## AI System Design

### Two-Stage Pipeline

The pipeline runs two sequential Claude calls per session:

**Stage 1 — Therapist Plan** (`temperature: 0.3`)
- Input: numbered transcript lines
- Output: `TherapistPlanContent` — structured clinical plan with citations
- Citations reference specific line numbers from the transcript
- Sections: presenting concerns, goals, interventions, homework, strengths, barriers

**Stage 2 — Client View** (`temperature: 0.5`)
- Input: therapist plan JSON
- Output: `ClientPlanContent` — plain-language client summary
- Strips all clinical jargon, risk indicators, and citations
- Sections: what we talked about, goals, things to try, your strengths

### Prompt Strategy
- System prompt establishes clinical documentation context
- Transcript lines are pre-numbered for precise citation (`[1] Therapist: ...`)
- JSON output enforced via strong prompt instruction + Pydantic validation
- Retry-once on validation failure with error context

### Model Choice
Claude Sonnet 4.6: 200k context window handles full session transcripts; strong clinical reasoning with structured output capability.

### Safety Detection (3 Layers)
1. **AI-embedded**: The therapist plan prompt explicitly asks Claude to identify safety concerns in its clinical impressions
2. **Regex patterns**: Post-pipeline scan for suicidal ideation, self-harm, harm to others, substance crisis, severe distress using compiled regex
3. **Deduplication**: Regex skips lines already covered by AI-detected flags

---

## Key Product Decisions

**Why dual views (therapist vs client)?**
Clinical documentation uses terminology and severity language inappropriate for clients. The two-view architecture lets therapists see the full clinical picture while clients receive an empowering, accessible summary.

**Why therapist approval gate?**
AI-generated content must be reviewed before client-facing use. The approval workflow ensures therapist accountability and creates a natural checkpoint for safety flag review.

**Why version immutability?**
Each edit creates a new version rather than overwriting. This preserves audit trail, enables diff comparison, and supports regulatory/liability requirements in clinical settings.

**Why citation-based explainability?**
Citations (line references back to the transcript) let therapists quickly verify that AI-generated clinical claims are grounded in what was actually said — preventing hallucination acceptance.

---

## Evaluation Framework

The evaluation framework validates AI output quality across 5 synthetic fixture transcripts.

### What It Measures
1. **Structural Validation** — all required sections present, citation bounds valid, no clinical jargon in client view, no risk data in client view
2. **Readability Analysis** — client plan <= 8th grade Flesch-Kincaid, therapist plan >= 2 grade levels above client
3. **Safety Detection** — flags detected for crisis/substance transcripts, no false positives for relationship/anxiety transcripts

### How to Run
```bash
# Via API (streams SSE progress)
curl -N -X POST http://localhost:8000/api/evaluation/run \
  -H "Authorization: Bearer $TOKEN"

# Or via the Evaluation page in the therapist dashboard
# Navigate to /therapist/evaluation -> click "Run Evaluation"
```

### Fixture Transcripts
| File | Scenario | Expected Safety Flags |
|------|----------|-----------------------|
| anxiety.txt | GAD, work stress, sleep issues | 0 |
| depression.txt | Moderate depression, withdrawal | 0 |
| crisis.txt | Passive suicidal ideation | >= 1 |
| substance.txt | Alcohol misuse, blackout | >= 1 |
| relationship.txt | Marital conflict, anger | 0 |

---

## Testing

```bash
cd backend
source venv/bin/activate
pytest tests/ -v
```

### Test Coverage
- `test_ai_output_parsing.py` — Pydantic schema validation (valid, invalid, edge cases)
- `test_safety_detection.py` — Regex flag detection + false positive resistance + deduplication
- `test_plan_validation.py` — Citation bounds, jargon detection, risk data detection
- `test_readability.py` — Grade level thresholds, clinical vs plain text comparison

---

## Limitations & Future Work

- **No audio/video processing** — transcripts must be text; future: Whisper transcription integration
- **No real-time collaboration** — therapist and client views are async; future: WebSocket live updates
- **No therapist preference learning** — future: few-shot example library personalized per therapist
- **No multi-language support** — all prompts assume English; future: Claude multilingual prompting
- **Demo-grade auth** — JWT with no refresh, no session management; future: OAuth 2.0, session storage
- **Single-tenant** — one therapist per instance; future: multi-tenant with org/practice isolation
