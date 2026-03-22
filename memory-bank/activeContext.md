# Active Context

## Current Focus

*Update this file as work progresses. Use it to track what the team is actively working on.*

- **Last updated:** 2025-03-22
- **Status:** Phase 1 Chat Agent Pipeline in Rails complete. 224 RSpec examples passing. Python backend (179 pytest) remains reference. Ready for Phase 2 (Onboarding + Provider Search).

## Active Work Areas

- Phase 1 signed off: chat agent pipeline, redaction, safety, scheduling, emotional support, OCR
- Next: Phase 2 — Onboarding routing, OnboardingProgress state, search_therapists tool, deep link `GET /api/onboard/:slug`

## Quick Reference

- Demo accounts: therapist@demo.health / client@demo.health — password: demo123
- Python backend: `cd backend && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000`
- Rails backend: `cd backend_rails && rbenv exec bundle exec rails s` (use rbenv; system Ruby 2.6 has bundler mismatch)
- Rails tests: `cd backend_rails && rbenv exec bundle exec rspec`
- Python tests: `cd backend && .venv/bin/python -m pytest tests/`
- Frontend: `cd frontend && npm run dev` (port 5173)
- Docker: `docker-compose up -d` (Postgres 5433, MinIO 9002, LiveKit 7880)
