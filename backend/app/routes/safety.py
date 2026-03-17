from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.models.client import Client
from app.models.safety_flag import SafetyFlag
from app.models.session import Session
from app.models.user import User
from app.schemas.safety import SafetyFlagResponse

router = APIRouter(tags=["safety"])


@router.get(
    "/api/sessions/{session_id}/safety-flags",
    response_model=list[SafetyFlagResponse],
)
async def get_session_safety_flags(
    session_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Therapist profile not found")

    # Verify session belongs to therapist
    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.therapist_id == therapist.id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Session not found")

    flag_result = await db.execute(
        select(SafetyFlag).where(SafetyFlag.session_id == session_id)
    )
    flags = flag_result.scalars().all()
    return [SafetyFlagResponse.model_validate(f) for f in flags]


@router.get(
    "/api/clients/{client_id}/safety-flags",
    response_model=list[SafetyFlagResponse],
)
async def get_client_safety_flags(
    client_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Therapist profile not found")

    # Verify client belongs to therapist
    result = await db.execute(
        select(Client).where(
            Client.id == client_id,
            Client.therapist_id == therapist.id,
        )
    )
    client = result.scalar_one_or_none()
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client not found")

    # Get all safety flags from the client's sessions
    flag_result = await db.execute(
        select(SafetyFlag)
        .join(Session, SafetyFlag.session_id == Session.id)
        .where(Session.client_id == client_id)
        .order_by(SafetyFlag.created_at.desc())
    )
    flags = flag_result.scalars().all()
    return [SafetyFlagResponse.model_validate(f) for f in flags]


@router.patch(
    "/api/safety-flags/{flag_id}/acknowledge",
    response_model=SafetyFlagResponse,
)
async def acknowledge_flag(
    flag_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(SafetyFlag).where(SafetyFlag.id == flag_id)
    )
    flag = result.scalar_one_or_none()
    if flag is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Safety flag not found")

    # Verify the flag's session belongs to this therapist
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Therapist profile not found")

    if flag.session_id:
        sess_result = await db.execute(
            select(Session).where(
                Session.id == flag.session_id,
                Session.therapist_id == therapist.id,
            )
        )
        if sess_result.scalar_one_or_none() is None:
            raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Not your safety flag")

    flag.acknowledged = True
    flag.acknowledged_at = datetime.utcnow()
    flag.acknowledged_by = therapist_user.id
    await db.commit()
    await db.refresh(flag)
    return SafetyFlagResponse.model_validate(flag)
