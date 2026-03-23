# Active Context

## Current Focus

*Update this file as work progresses. Use it to track what the team is actively working on.*

- **Last updated:** 2025-03-22
- **Status:** Rails is the primary backend. Chat agent pipeline, onboarding, documents, scheduling, and escalation implemented.

## Active Work Areas

- Full Rails migration complete per `docs/IMPLEMENTATION_PLAN.md`
- Deployment: Dockerfile builds Rails + frontend for Railway

## Quick Reference

- Demo accounts: therapist@demo.health / client@demo.health — password: demo123
- Rails backend: `cd backend_rails && bundle exec rails s -p 8000`
- Rails tests: `cd backend_rails && bundle exec rspec`
- Frontend: `cd frontend && npm run dev` (port 5173, expects backend on 8000)
- Docker: `docker-compose up -d` (Postgres 5433, MinIO 9002, LiveKit 7880)
