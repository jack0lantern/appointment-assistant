# System Patterns

## AI Pipeline (Two-Stage)

1. **Stage 1 — Therapist Plan** (temperature: 0.3)
   - Input: numbered transcript lines
   - Output: `TherapistPlanContent` — structured clinical plan with citations
   - Sections: presenting concerns, goals, interventions, homework, strengths, barriers

2. **Stage 2 — Client View** (temperature: 0.5)
   - Input: therapist plan JSON
   - Output: `ClientPlanContent` — plain-language client summary
   - Strips clinical jargon, risk indicators, citations

## Safety Detection (3 Layers)

1. **AI-embedded** — Therapist plan prompt asks Claude to identify safety concerns.
2. **Regex patterns** — Post-pipeline scan for suicidal ideation, self-harm, harm to others, substance crisis, severe distress.
3. **Deduplication** — Regex skips lines already covered by AI-detected flags.

## TDD (Mandatory)

Per `.agents/skills/test-driven-development/SKILL.md`:

1. Write failing test first (RED)
2. Verify it fails
3. Write minimal code to pass (GREEN)
4. Refactor while green

**No exceptions.** All production code must have a failing test written first.

## Shared Contracts First

- Blueprinter serializers in `backend_rails/app/blueprints/` and JSON contracts define response shapes.
- Define contracts before any agent builds.
- All agents build to these contracts.
