"""Evaluation endpoints — trigger evaluation runs and fetch results."""
import json
import traceback
from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.models.evaluation_run import EvaluationRun
from app.models.user import User
from app.schemas.evaluation import EvaluationRunResponse

router = APIRouter(prefix="/api/evaluation", tags=["evaluation"])

FIXTURE_DIR = str(Path(__file__).resolve().parent.parent.parent / "evaluation" / "fixtures")


def _sse_event(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


@router.post("/run")
async def run_evaluation(
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Run evaluation on all fixture transcripts, stream progress via SSE."""
    async def event_stream():
        from app.services.evaluation_service import run_evaluation as _run_eval
        try:
            yield _sse_event("progress", {"message": "Starting evaluation run..."})
            result = await _run_eval(FIXTURE_DIR)
            yield _sse_event("progress", {"message": f"Processed {result.total_transcripts} transcripts"})

            # Persist result
            run = EvaluationRun(
                results=result.model_dump(),
                overall_pass=result.overall_pass,
            )
            db.add(run)
            await db.commit()
            await db.refresh(run)

            yield _sse_event("complete", result.model_dump())
        except Exception as e:
            yield _sse_event("error", {"message": str(e), "traceback": traceback.format_exc()})

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
    )


@router.get("/results", response_model=list[EvaluationRunResponse])
async def list_results(
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Return past evaluation runs (most recent first, limit 10)."""
    result = await db.execute(
        select(EvaluationRun)
        .order_by(EvaluationRun.run_at.desc())
        .limit(10)
    )
    runs = result.scalars().all()
    return [EvaluationRunResponse(**r.results) for r in runs]
