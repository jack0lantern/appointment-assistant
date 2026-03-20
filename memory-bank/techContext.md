# Tech Context

## Stack

| Layer | Choice |
|-------|--------|
| Backend | Python 3.11+ + FastAPI (async) |
| ORM | SQLAlchemy 2.0 (async) + Alembic |
| Database | PostgreSQL (port 5433, JSONB for plan content) |
| AI | Anthropic SDK, Claude Sonnet 4.6 |
| Frontend | React 18 + Vite + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui |
| Auth | JWT (demo-grade) |
| Storage | S3/MinIO for recordings |
| Realtime | LiveKit (voice/agents) |
| Evaluation | textstat (readability), Pydantic (structural) |

## Key Paths

- `backend/app/` — Models, schemas, routes, services, prompts, utils
- `backend/app/schemas/` — Pydantic contracts (auth, client, session, treatment_plan, safety, homework, evaluation)
- `backend/app/services/ai_pipeline.py` — Two-stage AI pipeline (therapist plan → client view)
- `backend/app/utils/safety_patterns.py` — Regex safety detection
- `frontend/src/` — React app, pages, components

## Env & Config

- `backend/.env` — ANTHROPIC_API_KEY, DATABASE_URL, JWT_SECRET, S3_*, LIVEKIT_*, ASSEMBLYAI_API_KEY
- Use `backend/.venv` — never create a new venv (per `.cursor/rules/python-venv.mdc`)
