"""API routes for live therapy sessions (WebRTC via LiveKit)."""

from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, get_current_user, require_therapist
from app.models.client import Client
from app.models.recording_consent import RecordingConsent
from app.models.session import Session
from app.models.transcript import Transcript
from app.models.user import User
from app.schemas.live_session import (
    LiveSessionCreate,
    LiveSessionResponse,
    LiveSessionToken,
    LiveSessionStatus,
    RecordingConsentRequest,
    RecordingConsentResponse,
    RecordingStatusResponse,
    SpeakerMapRequest,
    TranscriptPreview,
)
from app.services.livekit_service import livekit_service

router = APIRouter(prefix="/api", tags=["live-sessions"])


# ── Helpers ────────────────────────────────────────────────────────────────────


async def _verify_client_ownership(
    client_id: int, therapist_user: User, db: AsyncSession
) -> Client:
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Therapist profile not found")
    result = await db.execute(
        select(Client).where(Client.id == client_id, Client.therapist_id == therapist.id)
    )
    client = result.scalar_one_or_none()
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Client not found")
    return client


async def _get_session(session_id: int, db: AsyncSession) -> Session:
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
    return session


# ── Live Session Lifecycle ─────────────────────────────────────────────────────


@router.post(
    "/clients/{client_id}/sessions/live",
    response_model=LiveSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_live_session(
    client_id: int,
    body: LiveSessionCreate,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Create a new live therapy session and provision a LiveKit room."""
    client = await _verify_client_ownership(client_id, therapist_user, db)
    therapist = therapist_user.therapist_profile

    # Determine next session number
    count_result = await db.execute(
        select(func.count()).select_from(Session).where(Session.client_id == client_id)
    )
    next_number = (count_result.scalar() or 0) + 1

    room_name = livekit_service.make_room_name(next_number * 1000 + client_id)

    session = Session(
        therapist_id=therapist.id,
        client_id=client.id,
        session_date=body.session_date or datetime.now(timezone.utc),
        session_number=next_number,
        duration_minutes=body.duration_minutes,
        status="in_progress",
        session_type="live",
        livekit_room_name=room_name,
        live_session_data={"started_at": datetime.now(timezone.utc).isoformat(), "participants": []},
    )
    db.add(session)
    await db.flush()

    # Use actual session ID for room name (more reliable)
    room_name = livekit_service.make_room_name(session.id)
    session.livekit_room_name = room_name

    # Create LiveKit room
    try:
        await livekit_service.create_room(room_name)
    except Exception as e:
        # Room creation failed but session is saved — room can be created lazily on token request
        pass

    await db.commit()
    await db.refresh(session)
    return LiveSessionResponse.model_validate(session)


@router.post(
    "/sessions/{session_id}/live/token",
    response_model=LiveSessionToken,
)
async def get_session_token(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a LiveKit token for the current user to join the session room."""
    session = await _get_session(session_id, db)

    if session.session_type != "live":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a live session")

    if session.status == "completed":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Session already ended")

    if not session.livekit_room_name:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "No room configured")

    # Verify user is a participant (therapist or client)
    is_therapist = (
        current_user.therapist_profile
        and current_user.therapist_profile.id == session.therapist_id
    )
    is_client = (
        current_user.client_profile
        and current_user.client_profile.id == session.client_id
    )
    if not is_therapist and not is_client:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not a participant in this session")

    role = "therapist" if is_therapist else "client"
    token = livekit_service.generate_token(
        room_name=session.livekit_room_name,
        participant_identity=f"{role}_{current_user.id}",
        participant_name=current_user.name,
    )

    # Peer name for UI ("Session with {peer_name}")
    peer_name = (
        session.client.name
        if is_therapist
        else (session.therapist.user.name if session.therapist and session.therapist.user else "Therapist")
    )

    # Track participant in live_session_data
    participants = (session.live_session_data or {}).get("participants", [])
    participant_entry = {
        "user_id": current_user.id,
        "role": role,
        "joined_at": datetime.now(timezone.utc).isoformat(),
    }
    # Don't duplicate
    if not any(p.get("user_id") == current_user.id for p in participants):
        participants.append(participant_entry)
        session.live_session_data = {**(session.live_session_data or {}), "participants": participants}
        await db.commit()

    return LiveSessionToken(
        token=token,
        room_name=session.livekit_room_name,
        server_url=livekit_service.url.replace("ws://", "ws://").replace("wss://", "wss://"),
        peer_name=peer_name,
    )


@router.post("/sessions/{session_id}/live/end")
async def end_live_session(
    session_id: int,
    background_tasks: BackgroundTasks,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """End a live session. Only the therapist can end it."""
    session = await _get_session(session_id, db)

    if session.session_type != "live":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a live session")

    therapist = therapist_user.therapist_profile
    if not therapist or therapist.id != session.therapist_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not the session therapist")

    # Stop recording if active
    if session.recording_status == "recording" and session.recording_egress_id:
        try:
            await livekit_service.stop_recording(session.recording_egress_id)
            session.recording_status = "stopped"
        except Exception:
            pass

    # Close LiveKit room
    if session.livekit_room_name:
        try:
            await livekit_service.close_room(session.livekit_room_name)
        except Exception:
            pass

    # Update session
    session.status = "completed"
    data = session.live_session_data or {}
    data["ended_at"] = datetime.now(timezone.utc).isoformat()
    session.live_session_data = data

    # Calculate actual duration
    started_at = data.get("started_at")
    if started_at:
        start = datetime.fromisoformat(started_at)
        end = datetime.now(timezone.utc)
        session.duration_minutes = max(1, int((end - start).total_seconds() / 60))

    await db.commit()

    # Trigger recording processing if recording was made
    if session.recording_status == "stopped" and session.recording_storage_path:
        session.recording_status = "processing"
        await db.commit()
        from app.workers.transcript_worker import process_recording
        background_tasks.add_task(process_recording, session_id, db)

    return {"status": "ended", "session_id": session_id}


@router.get("/sessions/{session_id}/live/status", response_model=LiveSessionStatus)
async def get_live_session_status(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current status of a live session."""
    session = await _get_session(session_id, db)

    data = session.live_session_data or {}
    participants = data.get("participants", [])

    duration_seconds = 0
    started_at = data.get("started_at")
    if started_at and session.status == "in_progress":
        start = datetime.fromisoformat(started_at)
        duration_seconds = int((datetime.now(timezone.utc) - start).total_seconds())

    return LiveSessionStatus(
        is_active=session.status == "in_progress",
        session_id=session.id,
        room_name=session.livekit_room_name,
        participants=participants,
        duration_seconds=duration_seconds,
        recording_status=session.recording_status,
    )


# ── Recording & Consent ───────────────────────────────────────────────────────


@router.post("/sessions/{session_id}/recording/consent", response_model=RecordingConsentResponse)
async def submit_recording_consent(
    session_id: int,
    body: RecordingConsentRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Submit recording consent for the current user."""
    session = await _get_session(session_id, db)

    if session.session_type != "live":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a live session")

    # Upsert consent record
    result = await db.execute(
        select(RecordingConsent).where(
            RecordingConsent.session_id == session_id,
            RecordingConsent.user_id == current_user.id,
        )
    )
    consent = result.scalar_one_or_none()

    client_ip = request.client.host if request.client else None

    if consent:
        consent.consented = body.consented
        consent.consented_at = datetime.now(timezone.utc) if body.consented else None
        consent.ip_address = client_ip
    else:
        consent = RecordingConsent(
            session_id=session_id,
            user_id=current_user.id,
            consented=body.consented,
            consented_at=datetime.now(timezone.utc) if body.consented else None,
            ip_address=client_ip,
        )
        db.add(consent)

    await db.commit()
    await db.refresh(consent)
    return RecordingConsentResponse.model_validate(consent)


@router.get("/sessions/{session_id}/recording/status", response_model=RecordingStatusResponse)
async def get_recording_status(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get recording status and consent state for a session."""
    session = await _get_session(session_id, db)

    result = await db.execute(
        select(RecordingConsent).where(RecordingConsent.session_id == session_id)
    )
    consents = result.scalars().all()

    all_consented = len(consents) >= 2 and all(c.consented for c in consents)

    return RecordingStatusResponse(
        recording_status=session.recording_status,
        all_consented=all_consented,
        consents=[RecordingConsentResponse.model_validate(c) for c in consents],
    )


@router.post("/sessions/{session_id}/recording/start")
async def start_recording(
    session_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Start recording a live session. Requires both participants to have consented."""
    session = await _get_session(session_id, db)

    if session.session_type != "live" or session.status != "in_progress":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Session not active")

    if session.recording_status == "recording":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Already recording")

    # Check all consents
    result = await db.execute(
        select(RecordingConsent).where(RecordingConsent.session_id == session_id)
    )
    consents = result.scalars().all()
    if len(consents) < 2 or not all(c.consented for c in consents):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Both participants must consent before recording")

    # Start LiveKit egress
    from app.services.storage_service import StorageService
    output_path = StorageService.recording_key(session_id)

    try:
        egress_id = await livekit_service.start_recording(
            session.livekit_room_name,
            output_path,
        )
    except Exception as e:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, f"Failed to start recording: {e}")

    session.recording_status = "recording"
    session.recording_egress_id = egress_id
    session.recording_storage_path = output_path
    await db.commit()

    return {"status": "recording", "egress_id": egress_id}


@router.post("/sessions/{session_id}/recording/stop")
async def stop_recording(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Stop recording. Either participant can stop."""
    session = await _get_session(session_id, db)

    if session.recording_status != "recording":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not currently recording")

    if session.recording_egress_id:
        try:
            await livekit_service.stop_recording(session.recording_egress_id)
        except Exception:
            pass

    session.recording_status = "stopped"
    await db.commit()

    return {"status": "stopped"}


# ── Transcript Review ──────────────────────────────────────────────────────────


@router.get("/sessions/{session_id}/transcript/preview", response_model=TranscriptPreview)
async def get_transcript_preview(
    session_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Get the diarized transcript preview for speaker assignment."""
    session = await _get_session(session_id, db)

    if not session.transcript or not session.transcript.utterances:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No diarized transcript available")

    utterances = session.transcript.utterances
    speakers = sorted({u.get("speaker", "unknown") for u in utterances})

    # Calculate duration from utterances
    duration = 0.0
    if utterances:
        duration = max(u.get("end_time", 0.0) for u in utterances)

    return TranscriptPreview(
        session_id=session_id,
        utterances=utterances,
        speakers=speakers,
        duration_seconds=duration,
    )


@router.post("/sessions/{session_id}/transcript/confirm")
async def confirm_speaker_map(
    session_id: int,
    body: SpeakerMapRequest,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Confirm speaker mapping and finalize the transcript for plan generation."""
    session = await _get_session(session_id, db)

    if not session.transcript or not session.transcript.utterances:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No diarized transcript available")

    transcript = session.transcript

    # Apply speaker map to utterances
    mapped_utterances = []
    for u in transcript.utterances:
        raw_speaker = u.get("speaker", u.get("speaker_raw", "unknown"))
        mapped_speaker = body.speaker_map.get(raw_speaker, raw_speaker)
        mapped_utterances.append({**u, "speaker": mapped_speaker})

    transcript.utterances = mapped_utterances
    transcript.speaker_map = body.speaker_map

    # Regenerate flat text with proper labels
    lines = []
    for u in mapped_utterances:
        label = u["speaker"].capitalize()
        lines.append(f"{label}: {u['text']}")
    transcript.content = "\n".join(lines)
    transcript.word_count = len(transcript.content.split())

    await db.commit()

    return {
        "status": "confirmed",
        "session_id": session_id,
        "word_count": transcript.word_count,
        "speaker_map": body.speaker_map,
    }
