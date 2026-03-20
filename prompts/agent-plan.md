Chat Agent Architecture Plan
Overview
A privacy-preserving conversational agent integrated into the existing Tava app, targeting client onboarding and appointment scheduling flows. The agent uses a tool-calling pattern (inspired by OpenEMR) where the LLM proposes actions and the backend executes them — the LLM never directly touches PII/PHI or performs state changes.

Architecture

┌─────────────────────────────────────────────────────────┐
│  Frontend (React)                                       │
│  ┌─────────────┐                                        │
│  │ ChatWidget   │ ← Floating button, bottom-right       │
│  │  ├ Messages  │    Sends: { message, sessionId,       │
│  │  ├ Input     │           contextType }               │
│  │  ├ QuickActions                                      │
│  │  └ DocUpload │                                       │
│  └─────────────┘                                        │
└──────────────────────┬──────────────────────────────────┘
                       │ POST /api/agent/chat
                       │ POST /api/agent/documents
┌──────────────────────▼──────────────────────────────────┐
│  Backend (FastAPI)                                       │
│                                                          │
│  ┌─────────────────────────────────────────────┐        │
│  │  Redaction Layer (redaction.py)              │        │
│  │  • Regex + pattern detection for PII/PHI    │        │
│  │  • Stable token mapping (server-side only)  │        │
│  │  • Field-level allowlist enforcement         │        │
│  └──────────────┬──────────────────────────────┘        │
│                  │                                        │
│  ┌──────────────▼──────────────────────────────┐        │
│  │  Agent Service (agent_service.py)            │        │
│  │  • Intent classification                     │        │
│  │  • Tool-calling loop (LLM → tools → LLM)    │        │
│  │  • Safety post-processing                    │        │
│  │  • Conversation persistence                  │        │
│  └──────┬───────┬───────┬──────────────────────┘        │
│         │       │       │                                │
│  ┌──────▼──┐ ┌──▼────┐ ┌▼──────────┐                   │
│  │Schedule │ │OCR    │ │Emotional  │                    │
│  │Service  │ │Service│ │Support    │                    │
│  │(secure) │ │(mask) │ │(guardrails│                    │
│  └─────────┘ └───────┘ └───────────┘                    │
│                                                          │
│  ┌─────────────────────────────────────────────┐        │
│  │  Anthropic SDK (Claude)                      │        │
│  │  Receives ONLY redacted/masked data          │        │
│  └─────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────┘
Key Security Decisions
Concern	Approach
PII in prompts	redaction.py replaces names, emails, phones, SSNs, policy numbers with stable tokens (PATIENT_001, EMAIL_A) before any LLM call. Server-side mapping dict, never serialized to LLM.
OCR data	Extracted text goes through redaction before use in prompts. Raw OCR stored encrypted server-side only.
Scheduling actions	LLM proposes actions using masked IDs; backend resolves real IDs and executes. All mutations require auth + server-side validation.
Harmful responses	Extend safety_patterns.py for agent responses. System prompt constrains: no diagnoses, no medication advice, crisis → emergency resources.
Audit trail	Log agent decisions and tool calls with masked data only. No PII in logs.
Field allowlist	Explicit list of fields permitted in LLM context. Everything else blocked.
Data Flow (Chat Message)
User sends message → backend receives with auth token
Backend loads conversation history from DB
Redaction layer scans user message + any referenced data, replaces PII with tokens
Redacted message + system prompt → Claude (tool-calling mode)
If Claude calls a tool (e.g., search_availability), backend executes it with real data, returns masked result to Claude
Claude generates response → safety check (safety_patterns.py) → post-process
Response sent to frontend with any suggested actions
New Files
Backend
backend/app/utils/redaction.py — PII detection, masking, token mapping
backend/app/services/agent_service.py — Core chat agent orchestration
backend/app/services/ocr_service.py — Document text extraction
backend/app/services/scheduling_service.py — Secure appointment operations
backend/app/services/emotional_support.py — Supportive content snippets
backend/app/routes/agent.py — /api/agent/* endpoints
backend/app/schemas/agent.py — Chat request/response schemas
backend/app/models/conversation.py — Conversation + message persistence
backend/tests/test_redaction.py
backend/tests/test_agent_service.py
backend/tests/test_agent_routes.py
backend/tests/test_scheduling_service.py
Frontend
frontend/src/components/chat/ChatWidget.tsx — Floating button + expandable panel
frontend/src/components/chat/ChatMessage.tsx — Message bubbles
frontend/src/components/chat/ChatInput.tsx — Input + send + upload
frontend/src/components/chat/QuickActions.tsx — Suggested action chips
frontend/src/components/chat/DocumentUpload.tsx — Image/doc upload in chat
frontend/src/hooks/useChat.ts — Chat state management hook
frontend/src/types/agent.ts — Agent-related TypeScript types
Implementation Order
Phase 1: Redaction layer + agent schemas + basic chat endpoint (TDD)
Phase 2: OCR service with redaction integration
Phase 3: Scheduling APIs with secure action execution
Phase 4: Frontend chat widget
Phase 5: Emotional support + guardrails tuning
Phase 6: Tests, polish, STUDY_GUIDE.md