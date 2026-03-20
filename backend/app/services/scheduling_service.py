"""Secure scheduling service for the chat agent.

All scheduling actions (book, reschedule, cancel) are executed server-side
with proper auth/validation. The LLM only proposes actions using masked IDs;
this service translates and executes them.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.session import Session
from app.models.client import Client
from app.models.therapist import Therapist

logger = logging.getLogger(__name__)


# ── Availability slots (demo implementation) ─────────────────────────────────
# In production, this would query a real calendar/scheduling system.

def generate_demo_slots(
    therapist_id: int,
    start_date: datetime | None = None,
    days_ahead: int = 7,
) -> list[dict[str, Any]]:
    """Generate demo availability slots for a therapist.

    Returns a list of slot dicts with stable IDs for booking.
    """
    if start_date is None:
        start_date = datetime.now(timezone.utc).replace(
            hour=0, minute=0, second=0, microsecond=0
        )

    slots: list[dict[str, Any]] = []
    slot_id = 1

    for day_offset in range(1, days_ahead + 1):
        day = start_date + timedelta(days=day_offset)
        # Skip weekends
        if day.weekday() >= 5:
            continue
        # Generate 3 slots per day: 9am, 1pm, 3pm
        for hour in [9, 13, 15]:
            slot_start = day.replace(hour=hour, minute=0)
            slot_end = slot_start + timedelta(minutes=50)
            slots.append({
                "id": f"slot-{therapist_id}-{slot_id}",
                "therapist_id": therapist_id,
                "start_time": slot_start.isoformat(),
                "end_time": slot_end.isoformat(),
                "duration_minutes": 50,
                "available": True,
            })
            slot_id += 1

    return slots


async def get_availability(
    db: AsyncSession,
    therapist_id: int,
    start_date: datetime | None = None,
) -> list[dict[str, Any]]:
    """Get available appointment slots for a therapist.

    In production, this would check against existing bookings.
    """
    # Verify therapist exists
    result = await db.execute(select(Therapist).where(Therapist.id == therapist_id))
    therapist = result.scalar_one_or_none()
    if not therapist:
        raise ValueError(f"Therapist {therapist_id} not found")

    return generate_demo_slots(therapist_id, start_date)


async def book_appointment(
    db: AsyncSession,
    client_id: int,
    therapist_id: int,
    slot_id: str,
    session_date: datetime | None = None,
    acting_therapist_id: int | None = None,
) -> dict[str, Any]:
    """Book an appointment. Server-side validation and execution.

    Args:
        db: Database session
        client_id: Verified client ID (from auth for clients, from request for therapist delegation)
        therapist_id: Therapist ID to book with
        slot_id: Slot ID from availability query
        session_date: Appointment datetime
        acting_therapist_id: If set, a therapist is booking on behalf of the client.
            The therapist-client relationship is validated server-side.

    Returns:
        Booking confirmation dict
    """
    # Validate client exists
    client_result = await db.execute(select(Client).where(Client.id == client_id))
    client = client_result.scalar_one_or_none()
    if not client:
        raise ValueError(f"Client {client_id} not found")

    # If a therapist is acting on behalf of a client, validate the relationship
    if acting_therapist_id is not None:
        relationship_result = await db.execute(
            select(Client).where(
                Client.id == client_id,
                Client.therapist_id == acting_therapist_id,
            )
        )
        if relationship_result.scalar_one_or_none() is None:
            raise ValueError(
                f"Therapist {acting_therapist_id} is not authorized to book for client {client_id}"
            )

    # Validate therapist exists
    therapist_result = await db.execute(select(Therapist).where(Therapist.id == therapist_id))
    therapist = therapist_result.scalar_one_or_none()
    if not therapist:
        raise ValueError(f"Therapist {therapist_id} not found")

    # In production: validate slot is still available, check for conflicts, etc.
    # For now, create a new session record
    if session_date is None:
        session_date = datetime.now(timezone.utc) + timedelta(days=1)

    # Count existing sessions for session_number
    count_result = await db.execute(
        select(Session).where(
            Session.client_id == client_id,
            Session.therapist_id == therapist_id,
        )
    )
    existing_count = len(count_result.scalars().all())

    new_session = Session(
        therapist_id=therapist_id,
        client_id=client_id,
        session_date=session_date,
        session_number=existing_count + 1,
        duration_minutes=50,
        status="scheduled",
        session_type="live",
    )
    db.add(new_session)
    await db.commit()
    await db.refresh(new_session)

    logger.info(
        "Appointment booked: session=%d client=%d therapist=%d slot=%s",
        new_session.id,
        client_id,
        therapist_id,
        slot_id,
    )

    return {
        "session_id": new_session.id,
        "status": "confirmed",
        "slot_id": slot_id,
        "session_date": session_date.isoformat(),
        "duration_minutes": 50,
    }


async def cancel_appointment(
    db: AsyncSession,
    session_id: int,
    client_id: int,
    acting_therapist_id: int | None = None,
) -> dict[str, Any]:
    """Cancel an existing appointment. Validates ownership.

    Args:
        db: Database session
        session_id: Session to cancel
        client_id: Client who owns the session
        acting_therapist_id: If set, a therapist is cancelling on behalf of the client.
            Validates that the session belongs to this therapist.
    """
    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.client_id == client_id,
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise ValueError("Session not found or access denied")

    # If therapist is acting on behalf, verify they own the session
    if acting_therapist_id is not None and session.therapist_id != acting_therapist_id:
        raise ValueError(
            f"Therapist {acting_therapist_id} is not authorized to cancel this session"
        )

    if session.status == "completed":
        raise ValueError("Cannot cancel a completed session")

    session.status = "cancelled"
    await db.commit()

    logger.info("Appointment cancelled: session=%d client=%d", session_id, client_id)

    return {
        "session_id": session_id,
        "status": "cancelled",
    }
