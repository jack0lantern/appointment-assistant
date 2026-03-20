"""Scheduling routes for the chat agent.

All scheduling actions are authenticated, server-validated, and auditable.
The LLM cannot directly execute these — it proposes actions, backend executes.

Supports two flows:
- **Client self-service**: client_id comes from JWT auth
- **Therapist delegation**: therapist books/cancels on behalf of their client
  (client_id from request body, therapist-client relationship validated server-side)
"""

from __future__ import annotations

import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.services.scheduling_service import (
    book_appointment,
    cancel_appointment,
    get_availability,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/agent/scheduling", tags=["agent-scheduling"])


class AvailabilityResponse(BaseModel):
    slots: list[dict]


class BookRequest(BaseModel):
    therapist_id: int
    slot_id: str
    session_date: datetime | None = None
    client_id: int | None = None  # Required for therapist delegation, ignored for clients


class BookResponse(BaseModel):
    session_id: int
    status: str
    slot_id: str
    session_date: str
    duration_minutes: int


class CancelRequest(BaseModel):
    session_id: int
    client_id: int | None = None  # Required for therapist delegation, ignored for clients


class CancelResponse(BaseModel):
    session_id: int
    status: str


@router.get("/availability", response_model=AvailabilityResponse)
async def availability(
    therapist_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AvailabilityResponse:
    """Get available appointment slots for a therapist."""
    try:
        slots = await get_availability(db, therapist_id)
        return AvailabilityResponse(slots=slots)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/book", response_model=BookResponse)
async def book(
    body: BookRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BookResponse:
    """Book an appointment.

    - **Client**: client_id from auth, body.client_id ignored
    - **Therapist**: body.client_id required, relationship validated server-side
    """
    if user.client_profile:
        # Client self-service: ID from auth, ignore body.client_id
        client_id = user.client_profile.id
        acting_therapist_id = None
    elif user.therapist_profile:
        # Therapist delegation: must specify which client
        if body.client_id is None:
            raise HTTPException(
                status_code=400,
                detail="Therapist must provide client_id when booking on behalf of a client",
            )
        client_id = body.client_id
        acting_therapist_id = user.therapist_profile.id
    else:
        raise HTTPException(status_code=403, detail="No client or therapist profile found")

    try:
        result = await book_appointment(
            db=db,
            client_id=client_id,
            therapist_id=body.therapist_id,
            slot_id=body.slot_id,
            session_date=body.session_date,
            acting_therapist_id=acting_therapist_id,
        )
        return BookResponse(**result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/cancel", response_model=CancelResponse)
async def cancel(
    body: CancelRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CancelResponse:
    """Cancel an appointment.

    - **Client**: client_id from auth, validates ownership
    - **Therapist**: body.client_id required, validates therapist owns the session
    """
    if user.client_profile:
        # Client self-service
        client_id = user.client_profile.id
        acting_therapist_id = None
    elif user.therapist_profile:
        # Therapist delegation
        if body.client_id is None:
            raise HTTPException(
                status_code=400,
                detail="Therapist must provide client_id when cancelling on behalf of a client",
            )
        client_id = body.client_id
        acting_therapist_id = user.therapist_profile.id
    else:
        raise HTTPException(status_code=403, detail="No client or therapist profile found")

    try:
        result = await cancel_appointment(
            db=db,
            session_id=body.session_id,
            client_id=client_id,
            acting_therapist_id=acting_therapist_id,
        )
        return CancelResponse(**result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
