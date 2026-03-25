# Appointment Assistant — AI Therapy Onboarding & Treatment Assistant

AI-powered mental health onboarding and treatment assistant. Helps clients with intake, document upload, therapist search, and appointment scheduling via a conversational chat agent. Includes treatment plan generation for therapists with safety evaluation built-in.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Backend | Ruby on Rails 7+ (API mode) |
| ORM | ActiveRecord + Rails migrations |
| Database | PostgreSQL (JSONB for plan content, onboarding progress) |
| Serialization | Blueprinter |
| AI Provider | Anthropic Claude Sonnet 4.6 |
| AI Integration | anthropic-rb (Ruby SDK) |
| Frontend | React 18 + Vite + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui |
| Auth | JWT (jwt gem + custom middleware) |
| Testing | RSpec + FactoryBot (backend) |

---

## Architecture

```
┌─────────────────────┐         ┌──────────────────────────────┐
│   Therapist Browser │◄───────►│  React + Vite Frontend       │
│   Client Browser    │         │  (port 5173)                 │
└─────────────────────┘         └──────────────┬───────────────┘
                                               │ HTTP / SSE
                                ┌──────────────▼───────────────┐
                                │  Rails API Backend           │
                                │  (port 3000 / 8000)          │
                                │                               │
                                │  ┌───────────────────────┐   │
                                │  │  AgentService          │   │
                                │  │  InputSafety → Redact │◄──┼──► Claude Sonnet 4.6
                                │  │  → LLM + Tools →       │   │
                                │  │  ResponseSafety        │   │
                                │  └───────────────────────┘   │
                                │                               │
                                └──────────────┬───────────────┘
                                               │
                                ┌──────────────▼───────────────┐
                                │  PostgreSQL (port 5430)       │
                                │  JSONB for plan content       │
                                └──────────────────────────────┘
```

**Chat limits** (per-message cap, LLM output cap, context vs. history): see [`docs/CHAT_LIMITS.md`](docs/CHAT_LIMITS.md).

---

## Quick Start

### Prerequisites
- Ruby 3.x (rbenv recommended)
- Node 18+
- Docker + Docker Compose

### Ruby setup (rbenv)

Using macOS system Ruby (`/usr/bin/ruby`) will cause permission errors when installing gems. Use rbenv instead:

```bash
# Install rbenv (Homebrew)
brew install rbenv ruby-build

# Install project Ruby version
rbenv install 3.3.10

# Add to ~/.zshrc (or ~/.bashrc)
eval "$(rbenv init - zsh)"

# Restart shell, then:
cd backend_rails
bundle install
```

### 1. Start PostgreSQL
```bash
docker-compose up -d
```

### 2. Backend (Rails) Setup
```bash
cd backend_rails
bundle install

# Copy and configure environment
cp .env.example .env
# Edit .env — set ANTHROPIC_API_KEY, DATABASE_URL

# Run migrations
bundle exec rails db:migrate

# Seed demo data (required for demo sign-in)
bundle exec rails db:seed

# Start server (port 8000 — matches frontend default)
bundle exec rails s -p 8000
```

### 3. Frontend Setup
```bash
cd frontend
npm install
npm run dev
# Opens at http://localhost:5173 (proxies API to backend on 8000)
```

### Demo Accounts

| Role | Email | Password |
|------|-------|----------|
| Therapist | therapist@demo.health | demo123 |
| Client | client@demo.health | demo123 |
| Client (new patient flow) | jordan.kim@demo.health | demo123 |

---

## Deploy to Railway

Deploy directly from GitHub with automatic deployments on push.

### 1. Create a Railway project

1. Go to [railway.app](https://railway.app) and sign in with GitHub.
2. Click **New Project** → **Deploy from GitHub repo**.
3. Select this repository and choose the branch to deploy (e.g. `main`).

### 2. Add PostgreSQL

1. In the project, click **+ New** → **Database** → **PostgreSQL**.
2. Railway provisions PostgreSQL and exposes `DATABASE_URL` to other services.

### 3. Add the app service

1. Click **+ New** → **GitHub Repo** and select this repo again (or add a new service from the same repo).
2. Railway detects the root `Dockerfile` and `railway.json` and builds the full-stack app (frontend + Rails backend).

### 4. Configure variables

In the app service → **Variables**, add or reference:

| Variable | Source | Notes |
|----------|--------|-------|
| `DATABASE_URL` | Reference from Postgres service | Use `${{Postgres.DATABASE_URL}}` |
| `ANTHROPIC_API_KEY` | Your key | Required for AI chat/plan generation |
| `JWT_SECRET` | Random string | Use a strong secret in production |
| `CORS_ORIGINS` | Your app URL | e.g. `https://your-app.up.railway.app` |
| `RAILS_ENV` | `production` | Required for Rails |
| `SECRET_KEY_BASE` | `rails secret` | Run `rails secret` locally to generate |

### 5. Connect Postgres to the app

1. In the app service → **Variables** → **Add Variable** → **Add Reference**.
2. Select the Postgres service and `DATABASE_URL`.

### 6. Generate a domain

1. In the app service → **Settings** → **Networking** → **Generate Domain**.
2. Your app will be available at `https://<service>-<project>.up.railway.app`.

### 7. Update CORS

After generating the domain, set `CORS_ORIGINS` to include it, e.g.:

```
https://your-app-name.up.railway.app
```

**Auto-deploy:** Pushes to the connected branch trigger new deployments. Configure the trigger branch in **Service Settings** → **Source**.

### Seeding production from local

To seed demo data in production (requires DB access from Railway CLI):

```bash
cd backend_rails
railway run bundle exec rails db:seed
```

Railway injects `DATABASE_URL` at runtime; the app connects from within the Railway network. If seeding from your local machine fails (private URL not reachable), enable the Postgres **TCP Proxy** and add `DATABASE_PUBLIC_URL` as a reference, then run with that URL in your local env.

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
# Via API (if evaluation endpoint is enabled)
curl -N -X POST http://localhost:8000/api/evaluation/run \
  -H "Authorization: Bearer $TOKEN"

# Or via the Evaluation page in the therapist dashboard
# Navigate to /therapist/evaluation -> click "Run Evaluation"

# Backend tests include safety, redaction, and plan validation
cd backend_rails && bundle exec rspec spec/services/

# Golden set (live LLM) — 17 tests that call Claude to verify agent output quality
# Requires ANTHROPIC_API_KEY; excluded from default rspec
cd backend_rails && bundle exec rspec spec/services/golden_set_eval_spec.rb --tag golden
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
cd backend_rails
bundle exec rspec
```

### Test Coverage
- `spec/services/redaction_service_spec.rb` — PII detection, stable tokens, restore
- `spec/services/agent_service_spec.rb` — Intent routing, safety checks, tool execution
- `spec/services/scheduling_service_spec.rb` — Slot generation, booking, therapist delegation
- `spec/requests/agent_chat_spec.rb` — Chat endpoint auth, validation, response shape

---

## Limitations & Future Work

- **No audio/video processing** — transcripts must be text; future: Whisper transcription integration
- **No real-time collaboration** — therapist and client views are async; future: WebSocket live updates
- **No therapist preference learning** — future: few-shot example library personalized per therapist
- **No multi-language support** — all prompts assume English; future: Claude multilingual prompting
- **Demo-grade auth** — JWT with no refresh, no session management; future: OAuth 2.0, session storage
- **Single-tenant** — one therapist per instance; future: multi-tenant with org/practice isolation
