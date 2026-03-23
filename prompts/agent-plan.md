Chat Agent Architecture Plan
Overview
A privacy-preserving conversational agent integrated into the existing app, targeting client onboarding and appointment scheduling flows. The agent uses a tool-calling pattern (inspired by OpenEMR) where the LLM proposes actions and the backend executes them — the LLM never directly touches PII/PHI or performs state changes.

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
│  Backend (Rails)                                          │
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
Key Files (Rails)
Backend
backend_rails/app/services/redaction_service.rb — PII detection, masking, token mapping
backend_rails/app/services/agent_service.rb — Core chat agent orchestration
backend_rails/app/services/ocr_service.rb — Document text extraction
backend_rails/app/services/scheduling_service.rb — Secure appointment operations
backend_rails/app/services/emotional_support_service.rb — Supportive content snippets
backend_rails/app/controllers/api/agent_controller.rb — /api/agent/* endpoints
backend_rails/app/blueprints/agent_blueprint.rb — Chat request/response serialization
backend_rails/app/models/conversation.rb — Conversation + message persistence
backend_rails/spec/services/redaction_service_spec.rb
backend_rails/spec/services/agent_service_spec.rb
backend_rails/spec/requests/agent_chat_spec.rb
backend_rails/spec/services/scheduling_service_spec.rb
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