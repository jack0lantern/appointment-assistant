# Tech Context

## Stack

| Layer | Choice |
|-------|--------|
| Backend | Ruby on Rails 7+ (API mode) |
| ORM | ActiveRecord + Rails migrations |
| Database | PostgreSQL (port 5433, JSONB for plan content, onboarding progress) |
| Serialization | Blueprinter |
| AI | anthropic-rb, Claude Sonnet 4.6 |
| Frontend | React 18 + Vite + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui |
| Auth | JWT (jwt gem) + custom middleware |
| Storage | S3/MinIO for recordings |
| Realtime | LiveKit (voice/agents) |
| Testing | RSpec + FactoryBot |

## Key Paths

- `backend_rails/app/` — Controllers, models, services, blueprints
- `backend_rails/app/services/agent_service.rb` — Chat agent pipeline orchestration
- `backend_rails/app/services/redaction_service.rb` — PII masking before LLM
- `backend_rails/app/services/` — InputSafety, SchedulingService, TherapistSearchService, etc.
- `backend_rails/app/blueprints/` — JSON serializers (contracts)
- `frontend/src/` — React app, pages, components
- `backend/` — Python reference implementation (legacy)

## Env & Config

- `backend_rails/.env` — ANTHROPIC_API_KEY, DATABASE_URL, JWT_SECRET, CORS_ORIGINS
