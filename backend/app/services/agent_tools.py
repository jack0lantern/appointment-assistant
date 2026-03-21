"""Tool definitions and execution for the chat agent.

Each tool is defined as an Anthropic tool-use schema (name, description, input_schema)
and has a corresponding async executor function. The AgentService passes these to the
LLM and executes whichever tools the LLM invokes.

Security notes:
- Tools that touch scheduling require auth context (user_id, role, client/therapist IDs).
  The executor validates these server-side — the LLM cannot forge identity.
- Tool results are redacted before being fed back to the LLM.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.emotional_support import (
    get_grounding_exercise,
    get_psychoeducation,
    get_validation_message,
    get_what_to_expect,
)
from app.services.scheduling_service import (
    book_appointment,
    cancel_appointment,
    get_availability,
)

logger = logging.getLogger(__name__)


# ── Tool schemas (Anthropic format) ─────────────────────────────────────────

TOOL_DEFINITIONS: list[dict[str, Any]] = [
    {
        "name": "get_current_datetime",
        "description": (
            "Returns the current date and time in UTC and the user's contextual "
            "timezone (defaults to US Mountain). Use this when the user mentions "
            "relative dates like 'next week', 'tomorrow', 'this Thursday', etc. "
            "so you can resolve them to actual dates."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_available_slots",
        "description": (
            "Fetches available appointment slots for a therapist over the next 7 days. "
            "Returns a list of slots with IDs, dates, times, and duration. "
            "Use this when the user wants to schedule or reschedule an appointment."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "therapist_id": {
                    "type": "integer",
                    "description": "The therapist's ID. Use the user's assigned therapist if known.",
                },
            },
            "required": ["therapist_id"],
        },
    },
    {
        "name": "book_appointment",
        "description": (
            "Books an appointment for the user (or the therapist's client in delegation mode). "
            "You MUST call get_available_slots first to get valid slot IDs. "
            "Pass the slot_id and therapist_id. The backend resolves the real client identity from auth."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "therapist_id": {
                    "type": "integer",
                    "description": "The therapist to book with.",
                },
                "slot_id": {
                    "type": "string",
                    "description": "The slot ID from get_available_slots.",
                },
                "client_id": {
                    "type": "integer",
                    "description": (
                        "Only required when a therapist is booking on behalf of a client. "
                        "Omit when the user is a client (their identity comes from auth)."
                    ),
                },
            },
            "required": ["therapist_id", "slot_id"],
        },
    },
    {
        "name": "cancel_appointment",
        "description": (
            "Cancels an existing appointment by session ID. "
            "The backend validates that the caller owns the session."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "session_id": {
                    "type": "integer",
                    "description": "The session ID to cancel.",
                },
                "client_id": {
                    "type": "integer",
                    "description": (
                        "Only required when a therapist is cancelling on behalf of a client. "
                        "Omit when the user is a client."
                    ),
                },
            },
            "required": ["session_id"],
        },
    },
    {
        "name": "get_grounding_exercise",
        "description": (
            "Returns a grounding or breathing exercise to help the user manage "
            "anxiety or emotional distress. Use this when the user is feeling "
            "overwhelmed, anxious, or asks for a calming technique."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_psychoeducation",
        "description": (
            "Returns brief psychoeducation content on a topic. "
            "Available topics: 'anxiety', 'first_session', 'therapy_general'. "
            "Use when the user asks about what therapy is like or about a mental health topic."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "topic": {
                    "type": "string",
                    "enum": ["anxiety", "first_session", "therapy_general"],
                    "description": "The psychoeducation topic.",
                },
            },
            "required": ["topic"],
        },
    },
    {
        "name": "get_what_to_expect",
        "description": (
            "Returns content about what the user can expect for a given stage. "
            "Available contexts: 'onboarding', 'first_appointment'. "
            "Use when the user asks what to expect or seems nervous about a step."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "context": {
                    "type": "string",
                    "enum": ["onboarding", "first_appointment"],
                    "description": "Which stage to describe.",
                },
            },
            "required": ["context"],
        },
    },
    {
        "name": "get_validation_message",
        "description": (
            "Returns a warm, validating message. Use this when the user shares "
            "difficult feelings and needs acknowledgment before anything else."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]


# ── Auth context passed to tool executors ────────────────────────────────────

class ToolAuthContext:
    """Encapsulates the authenticated user's identity for tool execution."""

    def __init__(
        self,
        user_id: int,
        role: str,
        client_id: int | None = None,
        therapist_id: int | None = None,
    ):
        self.user_id = user_id
        self.role = role
        self.client_id = client_id
        self.therapist_id = therapist_id


# ── Tool executors ──────────────────────────────────────────────────────────

async def execute_tool(
    tool_name: str,
    tool_input: dict[str, Any],
    auth: ToolAuthContext,
    db: AsyncSession | None = None,
) -> dict[str, Any]:
    """Execute a tool and return the result as a dict.

    All scheduling tools require a db session. Emotional support tools do not.
    """
    try:
        if tool_name == "get_current_datetime":
            return _exec_get_current_datetime()

        elif tool_name == "get_available_slots":
            if db is None:
                return {"error": "Database session required for scheduling"}
            return await _exec_get_available_slots(tool_input, db)

        elif tool_name == "book_appointment":
            if db is None:
                return {"error": "Database session required for scheduling"}
            return await _exec_book_appointment(tool_input, auth, db)

        elif tool_name == "cancel_appointment":
            if db is None:
                return {"error": "Database session required for scheduling"}
            return await _exec_cancel_appointment(tool_input, auth, db)

        elif tool_name == "get_grounding_exercise":
            return {"exercise": get_grounding_exercise()}

        elif tool_name == "get_psychoeducation":
            topic = tool_input.get("topic", "")
            content = get_psychoeducation(topic)
            if content is None:
                return {"error": f"Unknown topic: {topic}"}
            return {"content": content}

        elif tool_name == "get_what_to_expect":
            context = tool_input.get("context", "")
            content = get_what_to_expect(context)
            if content is None:
                return {"error": f"Unknown context: {context}"}
            return {"content": content}

        elif tool_name == "get_validation_message":
            return {"message": get_validation_message()}

        else:
            return {"error": f"Unknown tool: {tool_name}"}

    except ValueError as e:
        # Business logic errors (e.g., "not authorized", "not found")
        logger.warning("Tool %s business error: %s", tool_name, e)
        return {"error": str(e)}
    except Exception as e:
        logger.error("Tool %s unexpected error: %s", tool_name, e)
        return {"error": "An internal error occurred while executing this action."}


def _exec_get_current_datetime() -> dict[str, Any]:
    """Return current datetime info for the LLM to reason about dates."""
    now = datetime.now(timezone.utc)
    # Also provide Mountain Time as a convenience
    mountain_offset = timedelta(hours=-7)  # MDT
    mountain_now = now + mountain_offset

    return {
        "utc": now.isoformat(),
        "mountain_time": mountain_now.strftime("%Y-%m-%d %H:%M:%S MDT"),
        "date": now.strftime("%A, %B %d, %Y"),
        "day_of_week": now.strftime("%A"),
        "iso_date": now.strftime("%Y-%m-%d"),
    }


async def _exec_get_available_slots(
    tool_input: dict[str, Any],
    db: AsyncSession,
) -> dict[str, Any]:
    """Fetch available slots for a therapist."""
    therapist_id = tool_input["therapist_id"]
    slots = await get_availability(db, therapist_id)

    # Format slots for LLM readability
    formatted = []
    for slot in slots:
        start = datetime.fromisoformat(slot["start_time"])
        formatted.append({
            "slot_id": slot["id"],
            "date": start.strftime("%A, %B %d"),
            "time": start.strftime("%I:%M %p"),
            "duration_minutes": slot["duration_minutes"],
        })

    return {
        "therapist_id": therapist_id,
        "slots": formatted,
        "total": len(formatted),
    }


async def _exec_book_appointment(
    tool_input: dict[str, Any],
    auth: ToolAuthContext,
    db: AsyncSession,
) -> dict[str, Any]:
    """Book an appointment with auth-based identity resolution."""
    therapist_id = tool_input["therapist_id"]
    slot_id = tool_input["slot_id"]

    if auth.role == "client":
        # Client books for themselves
        if auth.client_id is None:
            return {"error": "No client profile found for this user"}
        result = await book_appointment(
            db=db,
            client_id=auth.client_id,
            therapist_id=therapist_id,
            slot_id=slot_id,
        )
    elif auth.role == "therapist":
        # Therapist delegation — client_id must come from tool input
        client_id = tool_input.get("client_id")
        if client_id is None:
            return {"error": "Therapist must specify client_id when booking on behalf of a client"}
        result = await book_appointment(
            db=db,
            client_id=client_id,
            therapist_id=therapist_id,
            slot_id=slot_id,
            acting_therapist_id=auth.therapist_id,
        )
    else:
        return {"error": "Only clients and therapists can book appointments"}

    return result


async def _exec_cancel_appointment(
    tool_input: dict[str, Any],
    auth: ToolAuthContext,
    db: AsyncSession,
) -> dict[str, Any]:
    """Cancel an appointment with auth-based ownership validation."""
    session_id = tool_input["session_id"]

    if auth.role == "client":
        if auth.client_id is None:
            return {"error": "No client profile found for this user"}
        result = await cancel_appointment(
            db=db,
            session_id=session_id,
            client_id=auth.client_id,
        )
    elif auth.role == "therapist":
        client_id = tool_input.get("client_id")
        if client_id is None:
            return {"error": "Therapist must specify client_id when cancelling on behalf of a client"}
        result = await cancel_appointment(
            db=db,
            session_id=session_id,
            client_id=client_id,
            acting_therapist_id=auth.therapist_id,
        )
    else:
        return {"error": "Only clients and therapists can cancel appointments"}

    return result
