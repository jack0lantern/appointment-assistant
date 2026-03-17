from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_client
from app.models.client import Client
from app.models.session import Session
from app.models.user import User
from app.schemas.session import SessionResponse
from app.schemas.treatment_plan import TreatmentPlanResponse, VersionResponse

router = APIRouter(prefix="/api/my", tags=["client_portal"])


@router.get("/treatment-plan")
async def get_my_treatment_plan(
    client_user: User = Depends(require_client),
    db: AsyncSession = Depends(get_db),
):
    client = client_user.client_profile
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client profile not found")

    plan = client.treatment_plan
    if plan is None or plan.status != "approved":
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="No approved treatment plan found",
        )

    current_version = plan.current_version
    client_content = current_version.client_content if current_version else None

    return {
        "plan": TreatmentPlanResponse.model_validate(plan),
        "client_content": client_content,
    }


@router.get("/sessions", response_model=list[dict])
async def get_my_sessions(
    client_user: User = Depends(require_client),
    db: AsyncSession = Depends(get_db),
):
    client = client_user.client_profile
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client profile not found")

    result = await db.execute(
        select(Session)
        .where(Session.client_id == client.id)
        .order_by(Session.session_date.desc().nullslast(), Session.id.desc())
    )
    sessions = result.scalars().all()

    return [
        {
            "session": SessionResponse.model_validate(s),
            "client_summary": s.summary.client_summary if s.summary else None,
        }
        for s in sessions
    ]


@router.get("/sessions/{session_id}")
async def get_my_session(
    session_id: int,
    client_user: User = Depends(require_client),
    db: AsyncSession = Depends(get_db),
):
    client = client_user.client_profile
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client profile not found")

    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.client_id == client.id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Session not found")

    return {
        "session": SessionResponse.model_validate(session),
        "client_summary": session.summary.client_summary if session.summary else None,
        "key_themes": session.summary.key_themes if session.summary else None,
    }
