from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.models.client import Client
from app.models.session import Session
from app.models.transcript import Transcript
from app.models.user import User
from app.schemas.safety import SafetyFlagResponse
from app.schemas.session import SessionCreate, SessionResponse, TranscriptResponse

router = APIRouter(tags=["sessions"])


async def _verify_client_ownership(
    client_id: int, therapist_user: User, db: AsyncSession
) -> Client:
    """Ensure the client belongs to this therapist."""
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Therapist profile not found",
        )
    result = await db.execute(
        select(Client).where(
            Client.id == client_id,
            Client.therapist_id == therapist.id,
        )
    )
    client = result.scalar_one_or_none()
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Client not found",
        )
    return client


@router.get(
    "/api/clients/{client_id}/sessions",
    response_model=list[SessionResponse],
)
async def list_sessions(
    client_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    await _verify_client_ownership(client_id, therapist_user, db)

    result = await db.execute(
        select(Session)
        .where(Session.client_id == client_id)
        .order_by(Session.session_date.desc().nullslast(), Session.id.desc())
    )
    sessions = result.scalars().all()
    return [SessionResponse.model_validate(s) for s in sessions]


@router.post(
    "/api/clients/{client_id}/sessions",
    response_model=SessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_session_json(
    client_id: int,
    body: SessionCreate,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Create a session with transcript from JSON body."""
    client = await _verify_client_ownership(client_id, therapist_user, db)
    therapist = therapist_user.therapist_profile

    # Determine next session number
    count_result = await db.execute(
        select(func.count()).select_from(Session).where(Session.client_id == client_id)
    )
    next_number = (count_result.scalar() or 0) + 1

    session = Session(
        therapist_id=therapist.id,
        client_id=client.id,
        session_date=body.session_date or datetime.utcnow(),
        session_number=next_number,
        duration_minutes=body.duration_minutes,
        status="completed",
    )
    db.add(session)
    await db.flush()

    transcript = Transcript(
        session_id=session.id,
        content=body.transcript_text,
        source_type="uploaded",
        word_count=len(body.transcript_text.split()),
    )
    db.add(transcript)
    await db.commit()
    await db.refresh(session)
    return SessionResponse.model_validate(session)


@router.post(
    "/api/clients/{client_id}/sessions/upload",
    response_model=SessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_session_file(
    client_id: int,
    file: UploadFile = File(...),
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Create a session with transcript from uploaded .txt file."""
    client = await _verify_client_ownership(client_id, therapist_user, db)
    therapist = therapist_user.therapist_profile

    content_bytes = await file.read()
    transcript_text = content_bytes.decode("utf-8")

    count_result = await db.execute(
        select(func.count()).select_from(Session).where(Session.client_id == client_id)
    )
    next_number = (count_result.scalar() or 0) + 1

    session = Session(
        therapist_id=therapist.id,
        client_id=client.id,
        session_date=datetime.utcnow(),
        session_number=next_number,
        duration_minutes=50,
        status="completed",
    )
    db.add(session)
    await db.flush()

    transcript = Transcript(
        session_id=session.id,
        content=transcript_text,
        source_type="uploaded",
        word_count=len(transcript_text.split()),
    )
    db.add(transcript)
    await db.commit()
    await db.refresh(session)
    return SessionResponse.model_validate(session)


@router.get("/api/sessions/{session_id}", response_model=dict)
async def get_session(
    session_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Therapist profile not found",
        )

    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.therapist_id == therapist.id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found",
        )

    response: dict = {
        "session": SessionResponse.model_validate(session),
        "transcript": None,
        "summary": None,
        "safety_flags": [],
    }

    if session.transcript:
        response["transcript"] = TranscriptResponse.model_validate(session.transcript)

    if session.summary:
        response["summary"] = {
            "id": session.summary.id,
            "session_id": session.summary.session_id,
            "therapist_summary": session.summary.therapist_summary,
            "client_summary": session.summary.client_summary,
            "key_themes": session.summary.key_themes,
        }

    if session.safety_flags:
        response["safety_flags"] = [
            SafetyFlagResponse.model_validate(f) for f in session.safety_flags
        ]

    return response
