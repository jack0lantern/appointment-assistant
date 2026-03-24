# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**Appointment Assistant** is an AI-powered mental health onboarding and treatment assistant. It provides a conversational chat agent for intake, document upload, therapist search, and appointment scheduling, plus treatment plan generation with safety evaluation built-in.

**Current Status:** Backend is Ruby on Rails. Chat agent pipeline, onboarding flows, and scheduling tools are implemented.

---

## How to Navigate This Repository

### Main Planning Document
- **docs/IMPLEMENTATION_PLAN.md** — The canonical implementation roadmap
  - Rails migration from Python/FastAPI
  - Phased plan: Chat agent → Onboarding → Documents → Escalation → Frontend
  - Shared contracts (Blueprinter serializers, API routes, state model)

### Supporting Documents
- **docs/TEST_PARITY_MATRIX.md** — Python→Rails test/route/contract mapping
- **docs/DEEP_LINK_CONTRACT.md** — `GET /api/onboard/:slug` auth and response shape
- **docs/DOCUMENT_RETENTION_POLICY.md** — Upload/OCR retention and purge
- **.agents/skills/test-driven-development/** — TDD discipline (red-green-refactor)

---

## Development Approach

### Test-Driven Development (Mandatory)
This project enforces **strict TDD** via `.agents/skills/test-driven-development/SKILL.md`:

1. **Write failing test first** (RED phase)
2. **Verify it fails correctly** before implementing
3. **Write minimal code to pass** (GREEN phase)
4. **Refactor while green** (REFACTOR phase)

**No exceptions:** All production code must have a failing test written first.

### Shared Contracts
- Blueprinter serializers in `app/blueprints/` define JSON response shapes
- API routes and request/response contracts documented in `docs/TEST_PARITY_MATRIX.md`
- `OnboardingProgress` JSONB schema on `conversations` table

---

## Technology Stack

| Layer | Choice |
|-------|--------|
| **Backend** | Ruby on Rails 7+ (API mode) |
| **ORM** | ActiveRecord + Rails migrations |
| **Database** | PostgreSQL (JSONB for plan content, onboarding progress) |
| **Serialization** | Blueprinter |
| **AI Integration** | anthropic-rb (Ruby SDK), Claude Sonnet 4.6 |
| **Frontend** | React + Vite + TypeScript |
| **Styling** | Tailwind CSS + shadcn/ui |
| **Auth** | JWT (jwt gem) + custom middleware |
| **Testing** | RSpec + FactoryBot (backend) |

---

## Project Structure

```
backend_rails/           # Rails API (primary backend)
  app/
    controllers/         # API endpoints
    models/              # ActiveRecord models
    services/            # Business logic (AgentService, RedactionService, etc.)
    blueprints/          # Blueprinter JSON serializers
    lib/                 # Utilities, prompts
  config/
  db/
  spec/                  # RSpec tests

frontend/                # React/Vite application
  src/

docker-compose.yml       # PostgreSQL, LiveKit, MinIO
```

---

## Key Conventions

### Environment Setup
- `backend_rails/.env.example` — ANTHROPIC_API_KEY, DATABASE_URL, JWT_SECRET, CORS_ORIGINS
- Copy to `backend_rails/.env` and populate

### Database Migrations
- Use Rails migrations: `rails g migration ...`
- Run with `rails db:migrate`

### AI Integration
- Anthropic Ruby SDK (`anthropic` gem)
- Prompts in service files and `lib/` helpers

### Testing Pattern (TDD)
1. Write spec → watch fail
2. Implement minimal code → watch pass
3. Refactor → keep green
4. Repeat

---

## Commands

```bash
# Start services
docker-compose up -d   # PostgreSQL (5430), MinIO, LiveKit

# Backend (Rails)
cd backend_rails
bundle install
bundle exec rails db:migrate
bundle exec rails s -p 8000

# Run tests
cd backend_rails
bundle exec rspec
bundle exec rspec spec/services/agent_service_spec.rb   # Single file

# Frontend
cd frontend
npm install
npm run dev   # Port 5173, expects backend on 8000
```

---

## References & Roles

- **Rails backend:** `backend_rails/` — controllers, services, models
- **Frontend:** `frontend/src/` — React pages and components
