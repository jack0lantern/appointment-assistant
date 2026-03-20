# Product Context

## Purpose

Generate personalized, evidence-based treatment plans from therapy session transcripts using Claude AI. The system supports therapy workflow management and safety evaluation.

## Key Flows

1. **Therapist uploads transcript** → AI generates therapist plan (clinical) + client view (plain language).
2. **Therapist reviews and approves** → Plan becomes visible to client.
3. **Edits create new versions** → Immutable history; diff comparison supported.
4. **Safety flags** → AI and regex detect crisis/substance concerns; therapist reviews before client sees plan.

## Product Decisions

| Decision | Rationale |
|----------|-----------|
| Dual views (therapist vs client) | Clinical terminology and severity language are inappropriate for clients. |
| Therapist approval gate | AI content must be reviewed before client-facing use. |
| Version immutability | Audit trail, diff comparison, regulatory/liability support. |
| Citation-based explainability | Line references let therapists verify AI claims against transcript. |
