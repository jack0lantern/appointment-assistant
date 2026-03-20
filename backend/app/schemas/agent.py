"""Pydantic schemas for the AI chat agent.

Defines request/response contracts for the /api/agent/* endpoints.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class AgentContextType(str, Enum):
    """High-level context the chat agent is operating in."""

    onboarding = "onboarding"
    scheduling = "scheduling"
    emotional_support = "emotional_support"
    document_upload = "document_upload"
    general = "general"


class ChatMessage(BaseModel):
    """A single message in the conversation."""

    role: str = Field(..., description="'user' or 'assistant'")
    content: str
    timestamp: datetime | None = None


class AgentChatRequest(BaseModel):
    """Request body for POST /api/agent/chat."""

    message: str = Field(..., min_length=1, max_length=4000)
    conversation_id: str | None = None
    context_type: AgentContextType = AgentContextType.general
    page_context: dict[str, Any] | None = Field(
        default=None,
        description="High-level page context (no raw PII). E.g. {'page': 'onboarding', 'step': 2}",
    )


class SuggestedAction(BaseModel):
    """A quick-action chip shown to the user."""

    label: str
    action_type: str = "message"
    payload: str | None = None


class SafetyMeta(BaseModel):
    """Safety/routing metadata attached to agent responses."""

    flagged: bool = False
    flag_type: str | None = None
    escalated: bool = False


class AgentChatResponse(BaseModel):
    """Response body for POST /api/agent/chat."""

    message: str
    conversation_id: str
    suggested_actions: list[SuggestedAction] = Field(default_factory=list)
    follow_up_questions: list[str] = Field(default_factory=list)
    safety: SafetyMeta = Field(default_factory=SafetyMeta)
    context_type: AgentContextType = AgentContextType.general


class AgentDocumentRequest(BaseModel):
    """Metadata sent alongside a document upload."""

    conversation_id: str | None = None
    document_type: str | None = Field(
        default=None,
        description="E.g. 'insurance_card', 'id_card', 'intake_form'",
    )


class ExtractedField(BaseModel):
    """A single field extracted from a document via OCR."""

    field_name: str
    value: str
    confidence: float | None = None


class AgentDocumentResponse(BaseModel):
    """Response for POST /api/agent/documents."""

    extracted_fields: list[ExtractedField] = Field(default_factory=list)
    raw_text_preview: str | None = Field(
        default=None,
        description="Short preview of extracted text (redacted).",
    )
    conversation_id: str | None = None


class ConversationHistoryResponse(BaseModel):
    """Response for GET /api/agent/conversations/{id}."""

    conversation_id: str
    messages: list[ChatMessage] = Field(default_factory=list)
    context_type: AgentContextType = AgentContextType.general
    created_at: datetime | None = None
