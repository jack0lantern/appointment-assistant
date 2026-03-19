import json
import traceback

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.models.homework_item import HomeworkItem
from app.models.safety_flag import SafetyFlag
from app.models.session import Session
from app.models.session_summary import SessionSummary
from app.models.treatment_plan import TreatmentPlan
from app.models.treatment_plan_version import TreatmentPlanVersion
from app.models.user import User

router = APIRouter(tags=["generate"])


def _sse_event(event: str, data: dict) -> str:
    """Format a server-sent event."""
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


@router.post("/api/sessions/{session_id}/generate")
async def generate_treatment_plan(
    session_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Therapist profile not found")

    # Verify session ownership
    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.therapist_id == therapist.id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Session not found")

    if session.transcript is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Session has no transcript",
        )

    transcript_text = session.transcript.content
    client_id = session.client_id

    async def event_stream():
        from app.services.ai_pipeline import run_pipeline

        try:
            # Stage 1: Check for existing plan (before pipeline so we can pass it)
            yield _sse_event("progress", {"stage": "saving", "message": "Checking for existing plan..."})

            plan_result = await db.execute(
                select(TreatmentPlan).where(TreatmentPlan.client_id == client_id)
            )
            plan = plan_result.scalar_one_or_none()

            existing_plan_content = None
            if plan is None:
                # Create new plan
                plan = TreatmentPlan(
                    client_id=client_id,
                    therapist_id=therapist.id,
                    status="draft",
                )
                db.add(plan)
                await db.flush()
                next_version_number = 1
                source = "ai_generated"
            else:
                # Existing plan — create new version, revert to draft
                latest_result = await db.execute(
                    select(TreatmentPlanVersion)
                    .where(TreatmentPlanVersion.treatment_plan_id == plan.id)
                    .order_by(TreatmentPlanVersion.version_number.desc())
                    .limit(1)
                )
                latest = latest_result.scalar_one_or_none()
                next_version_number = (latest.version_number if latest else 0) + 1
                source = "ai_updated"
                plan.status = "draft"
                existing_plan_content = latest.therapist_content if latest else None

            # Stage 2: Running pipeline
            yield _sse_event("progress", {"stage": "pipeline", "message": "Running AI analysis..."})

            pipeline_result = await run_pipeline(transcript_text, existing_plan=existing_plan_content)

            yield _sse_event("progress", {"stage": "pipeline_complete", "message": "Analysis complete"})

            # Stage 3: Create version
            yield _sse_event("progress", {"stage": "version", "message": "Creating plan version..."})

            version = TreatmentPlanVersion(
                treatment_plan_id=plan.id,
                version_number=next_version_number,
                session_id=session_id,
                therapist_content=pipeline_result.therapist_content.model_dump(),
                client_content=pipeline_result.client_content.model_dump(),
                change_summary=pipeline_result.change_summary or "AI-generated treatment plan",
                source=source,
                ai_metadata=pipeline_result.ai_metadata,
            )
            db.add(version)
            await db.flush()

            plan.current_version_id = version.id

            # Stage 4: Safety flags
            yield _sse_event("progress", {"stage": "safety_flags", "message": "Recording safety flags..."})

            for sf in pipeline_result.safety_flags:
                flag = SafetyFlag(
                    session_id=session_id,
                    treatment_plan_version_id=version.id,
                    flag_type=sf.flag_type.value if hasattr(sf.flag_type, "value") else sf.flag_type,
                    severity=sf.severity.value if hasattr(sf.severity, "value") else sf.severity,
                    description=sf.description,
                    transcript_excerpt=sf.transcript_excerpt,
                    line_start=sf.line_start,
                    line_end=sf.line_end,
                    source=sf.source,
                    category=sf.category.value if hasattr(sf.category, "value") else sf.category,
                )
                db.add(flag)

            # Stage 5: Homework items
            yield _sse_event("progress", {"stage": "homework", "message": "Creating homework items..."})

            for hw_desc in pipeline_result.homework_items:
                hw = HomeworkItem(
                    treatment_plan_version_id=version.id,
                    client_id=client_id,
                    description=hw_desc,
                )
                db.add(hw)

            # Stage 6: Session summary
            yield _sse_event("progress", {"stage": "summary", "message": "Saving session summary..."})

            summary = SessionSummary(
                session_id=session_id,
                therapist_summary=pipeline_result.therapist_session_summary,
                client_summary=pipeline_result.client_session_summary,
                key_themes=pipeline_result.key_themes,
            )
            db.add(summary)

            await db.commit()

            # Final event with results
            yield _sse_event("complete", {
                "treatment_plan_id": plan.id,
                "version_id": version.id,
                "version_number": next_version_number,
                "safety_flags_count": len(pipeline_result.safety_flags),
                "homework_items_count": len(pipeline_result.homework_items),
                "source": source,
            })

        except Exception as e:
            yield _sse_event("error", {
                "message": str(e),
                "traceback": traceback.format_exc(),
            })

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )
