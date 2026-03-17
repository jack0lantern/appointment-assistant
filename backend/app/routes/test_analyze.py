# DEV ONLY — remove or auth-gate for production

import time

from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status
from fastapi.params import Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db
from app.models.client import Client
from app.models.homework_item import HomeworkItem
from app.models.safety_flag import SafetyFlag
from app.models.session import Session
from app.models.session_summary import SessionSummary
from app.models.therapist import Therapist
from app.models.transcript import Transcript
from app.models.treatment_plan import TreatmentPlan
from app.models.treatment_plan_version import TreatmentPlanVersion
from app.models.user import User
from app.schemas.test_analyze import TranscriptAnalysisRequest, TranscriptAnalysisResponse
from app.services.auth_service import hash_password

router = APIRouter(prefix="/api/test", tags=["test"])

DEMO_THERAPIST_EMAIL = "therapist@tava.health"


async def _get_or_create_demo_therapist(db: AsyncSession) -> Therapist:
    """Look up or create the demo therapist user + profile."""
    result = await db.execute(
        select(User).where(User.email == DEMO_THERAPIST_EMAIL)
    )
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            email=DEMO_THERAPIST_EMAIL,
            name="Demo Therapist",
            role="therapist",
            password_hash=hash_password("password"),
        )
        db.add(user)
        await db.flush()

        therapist = Therapist(
            user_id=user.id,
            license_type="LCSW",
            specialties=["general"],
            preferences={},
        )
        db.add(therapist)
        await db.flush()
    else:
        therapist = user.therapist_profile
        if therapist is None:
            therapist = Therapist(
                user_id=user.id,
                license_type="LCSW",
                specialties=["general"],
                preferences={},
            )
            db.add(therapist)
            await db.flush()

    return therapist


async def _persist_pipeline_results(
    db: AsyncSession,
    therapist: Therapist,
    client: Client,
    session: Session,
    pipeline_result,
) -> TreatmentPlanVersion:
    """Save all pipeline outputs to the database, return the new version."""
    from sqlalchemy import func

    # Treatment plan: look up existing or create new
    # Use explicit async query — accessing client.treatment_plan directly triggers
    # a synchronous lazy load on a flushed-but-not-reloaded object → MissingGreenlet.
    plan_result = await db.execute(
        select(TreatmentPlan).where(TreatmentPlan.client_id == client.id)
    )
    plan = plan_result.scalar_one_or_none()
    if plan is None:
        plan = TreatmentPlan(
            client_id=client.id,
            therapist_id=therapist.id,
            status="draft",
        )
        db.add(plan)
        await db.flush()

    # Determine next version number
    result = await db.execute(
        select(TreatmentPlanVersion)
        .where(TreatmentPlanVersion.treatment_plan_id == plan.id)
        .order_by(TreatmentPlanVersion.version_number.desc())
        .limit(1)
    )
    latest = result.scalar_one_or_none()
    next_number = (latest.version_number if latest else 0) + 1
    source = "ai_updated" if latest else "ai_generated"

    version = TreatmentPlanVersion(
        treatment_plan_id=plan.id,
        version_number=next_number,
        session_id=session.id,
        therapist_content=pipeline_result.therapist_content.model_dump(),
        client_content=pipeline_result.client_content.model_dump(),
        change_summary=pipeline_result.change_summary or "AI-generated treatment plan",
        source=source,
        ai_metadata=pipeline_result.ai_metadata,
    )
    db.add(version)
    await db.flush()

    plan.current_version_id = version.id
    if source == "ai_updated":
        plan.status = "draft"

    # Safety flags
    for sf in pipeline_result.safety_flags:
        flag = SafetyFlag(
            session_id=session.id,
            treatment_plan_version_id=version.id,
            flag_type=sf.flag_type.value if hasattr(sf.flag_type, "value") else sf.flag_type,
            severity=sf.severity.value if hasattr(sf.severity, "value") else sf.severity,
            description=sf.description,
            transcript_excerpt=sf.transcript_excerpt,
            line_start=sf.line_start,
            line_end=sf.line_end,
            source=sf.source,
        )
        db.add(flag)

    # Homework items
    for hw_desc in pipeline_result.homework_items:
        hw = HomeworkItem(
            treatment_plan_version_id=version.id,
            client_id=client.id,
            description=hw_desc,
        )
        db.add(hw)

    # Session summary
    summary = SessionSummary(
        session_id=session.id,
        therapist_summary=pipeline_result.therapist_session_summary,
        client_summary=pipeline_result.client_session_summary,
        key_themes=pipeline_result.key_themes,
    )
    db.add(summary)

    await db.commit()
    await db.refresh(version)
    return version


@router.post("/analyze", response_model=TranscriptAnalysisResponse)
async def analyze_transcript_json(
    body: TranscriptAnalysisRequest,
    db: AsyncSession = Depends(get_db),
):
    """Analyze a transcript via JSON body. DEV ONLY."""
    return await _run_analysis(
        transcript_text=body.transcript_text,
        client_name=body.client_name,
        save=body.save,
        db=db,
    )


@router.post("/analyze/upload", response_model=TranscriptAnalysisResponse)
async def analyze_transcript_file(
    file: UploadFile = File(...),
    client_name: str = Form("Test Client"),
    save: bool = Form(True),
    db: AsyncSession = Depends(get_db),
):
    """Analyze a transcript via file upload. DEV ONLY.
    Usage: curl -F file=@transcript.txt http://localhost:8000/api/test/analyze/upload
    """
    content_bytes = await file.read()
    transcript_text = content_bytes.decode("utf-8")
    return await _run_analysis(
        transcript_text=transcript_text,
        client_name=client_name,
        save=save,
        db=db,
    )


async def _run_analysis(
    transcript_text: str,
    client_name: str,
    save: bool,
    db: AsyncSession,
) -> TranscriptAnalysisResponse:
    """Core analysis logic shared by JSON and file upload endpoints."""
    from app.services.ai_pipeline import run_pipeline

    start = time.time()

    session_id = None
    version_id = None

    if save:
        therapist = await _get_or_create_demo_therapist(db)

        # Create client
        client = Client(
            therapist_id=therapist.id,
            name=client_name,
        )
        db.add(client)
        await db.flush()

        # Create session
        from datetime import datetime
        from sqlalchemy import func

        count_result = await db.execute(
            select(func.count())
            .select_from(Session)
            .where(Session.client_id == client.id)
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

        # Create transcript
        transcript = Transcript(
            session_id=session.id,
            content=transcript_text,
            source_type="uploaded",
            word_count=len(transcript_text.split()),
        )
        db.add(transcript)
        await db.flush()

    # Run pipeline
    try:
        pipeline_result = await run_pipeline(transcript_text)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Pipeline failed: {str(e)}",
        )

    if save:
        version = await _persist_pipeline_results(
            db, therapist, client, session, pipeline_result
        )
        session_id = session.id
        version_id = version.id

    elapsed = time.time() - start

    return TranscriptAnalysisResponse(
        session_id=session_id,
        treatment_plan_version_id=version_id,
        pipeline_result=pipeline_result,
        safety_flags_detected=len(pipeline_result.safety_flags),
        homework_items_created=len(pipeline_result.homework_items),
        generation_time_seconds=round(elapsed, 2),
    )
