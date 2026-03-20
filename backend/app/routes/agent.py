"""Agent chat API routes.

POST /api/agent/chat — Main chat endpoint with redaction + safety + tool calling.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.schemas.agent import AgentChatRequest, AgentChatResponse
from app.services.agent_service import AgentService
from app.services.agent_tools import ToolAuthContext

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/agent", tags=["agent"])


def _build_auth_context(user: User) -> ToolAuthContext:
    """Build a ToolAuthContext from an authenticated user."""
    client_id = user.client_profile.id if user.client_profile else None
    therapist_id = user.therapist_profile.id if user.therapist_profile else None
    return ToolAuthContext(
        user_id=user.id,
        role=user.role,
        client_id=client_id,
        therapist_id=therapist_id,
    )


@router.post("/chat", response_model=AgentChatResponse)
async def chat(
    body: AgentChatRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AgentChatResponse:
    """Process a chat message through the agent pipeline.

    1. Redacts PII/PHI from user message
    2. Checks for crisis/safety signals
    3. Classifies intent
    4. Calls LLM with tool definitions — LLM may invoke tools in a loop
    5. Safety-checks the final response
    6. Returns structured response with suggested actions
    """
    service = AgentService()
    auth = _build_auth_context(user)

    # TODO: Load conversation history from DB using body.conversation_id
    history: list[dict[str, str]] = []

    response = await service.process_message(
        user_message=body.message,
        conversation_id=body.conversation_id,
        context_type=body.context_type,
        user_id=user.id,
        history=history,
        auth=auth,
        db=db,
    )

    # TODO: Persist user message + agent response to conversation_messages table

    return response
