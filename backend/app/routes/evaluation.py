"""Evaluation endpoints — trigger evaluation runs and fetch results."""
import asyncio
import json
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import PlainTextResponse, StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.models.evaluation_run import EvaluationRun
from app.models.user import User
from app.schemas.evaluation import (
    EvaluationRunResponse,
    SuggestionRequest,
    SuggestionResponse,
)

router = APIRouter(prefix="/api/evaluation", tags=["evaluation"])

FIXTURE_DIR = str(Path(__file__).resolve().parent.parent.parent / "evaluation" / "fixtures")

EvalSection = Literal["structural", "readability", "safety"]

# Module-level cancellation event for the current running evaluation
_cancel_event: asyncio.Event | None = None


def _sse_event(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


SECTION_LABELS: dict[EvalSection, str] = {
    "structural": "structural validation",
    "readability": "readability analysis",
    "safety": "safety detection",
}


def _create_run_handler(section: EvalSection | None):
    """Create a run handler for the given section (None = full run)."""

    async def _handler(
        therapist_user: User = Depends(require_therapist),
        db: AsyncSession = Depends(get_db),
    ):
        global _cancel_event
        from app.services.evaluation_service import run_evaluation_stream

        label = SECTION_LABELS.get(section, "evaluation") if section else "evaluation"

        async def event_stream():
            global _cancel_event
            cancel = asyncio.Event()
            _cancel_event = cancel
            results = []

            try:
                yield _sse_event("progress", {"message": f"Starting {label}..."})

                async for result, idx, total in run_evaluation_stream(FIXTURE_DIR, cancel):
                    results.append(result)
                    status = "✅" if result.structural.valid else "❌"
                    log_msg = f"{status} {result.transcript_name} — {result.generation_time_seconds}s"
                    yield _sse_event("log", {
                        "message": log_msg,
                        "index": idx,
                        "total": total,
                    })

                if cancel.is_set():
                    yield _sse_event("stopped", {"message": "Evaluation stopped by user"})
                    return

                passed_structural = sum(1 for r in results if r.structural.valid)
                passed_readability = sum(1 for r in results if r.readability.target_met)
                passed_safety = sum(1 for r in results if r.safety is None or r.safety.passed)

                overall_pass = (
                    passed_structural == len(results)
                    and passed_safety == len(results)
                )

                final_result = EvaluationRunResponse(
                    run_at=datetime.now(timezone.utc).isoformat(),
                    results=results,
                    overall_pass=overall_pass,
                    total_transcripts=len(results),
                    passed_structural=passed_structural,
                    passed_readability=passed_readability,
                    passed_safety=passed_safety,
                )

                run = EvaluationRun(
                    results=final_result.model_dump(),
                    overall_pass=final_result.overall_pass,
                )
                db.add(run)
                await db.commit()
                await db.refresh(run)

                yield _sse_event("complete", final_result.model_dump())

            except asyncio.CancelledError:
                yield _sse_event("stopped", {"message": "Evaluation cancelled"})
            except Exception as e:
                yield _sse_event("error", {"message": str(e), "traceback": traceback.format_exc()})
            finally:
                _cancel_event = None

        # Closure over db - we need to inject it. The handler receives db from Depends.
        # But the inner event_stream doesn't have access to the handler's db!
        # We need to pass db into the closure. The handler is called per-request, so
        # we can create the stream with db captured. Let me fix - the inner async def
        # will capture db from the outer scope. The outer scope is _handler, which
        # receives db. So we need event_stream to be defined inside _handler so it
        # captures db. It is - event_stream is inside _handler. So it captures db.
        # Good.

        return StreamingResponse(
            event_stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
        )

    return _handler


@router.post("/run")
async def run_evaluation(
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Run full evaluation on all fixture transcripts."""
    return await _create_run_handler(None)(therapist_user, db)


@router.post("/run/structural")
async def run_structural_evaluation(
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Run structural validation on all fixture transcripts."""
    return await _create_run_handler("structural")(therapist_user, db)


@router.post("/run/readability")
async def run_readability_evaluation(
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Run readability analysis on all fixture transcripts."""
    return await _create_run_handler("readability")(therapist_user, db)


@router.post("/run/safety")
async def run_safety_evaluation(
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    """Run safety detection on all fixture transcripts."""
    return await _create_run_handler("safety")(therapist_user, db)


@router.post("/stop")
async def stop_evaluation(therapist_user: User = Depends(require_therapist)):
    """Stop the currently running evaluation."""
    global _cancel_event
    if _cancel_event:
        _cancel_event.set()
        return {"message": "Evaluation stop requested"}
    return {"message": "No evaluation currently running"}


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


@router.get("/transcripts/{name}")
async def get_transcript_text(name: str) -> PlainTextResponse:
    """Return the raw text of a fixture transcript."""
    if "/" in name or "\\" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Invalid transcript name")
    filepath = Path(FIXTURE_DIR) / name
    if not filepath.exists():
        raise HTTPException(status_code=404, detail=f"Transcript '{name}' not found")
    return PlainTextResponse(filepath.read_text())


@router.post("/suggestions", response_model=SuggestionResponse)
async def get_suggestions(
    req: SuggestionRequest,
    therapist_user: User = Depends(require_therapist),
):
    """Generate LLM improvement suggestions for an evaluation result."""
    from app.services.evaluation_service import generate_suggestions

    suggestions = await generate_suggestions(
        transcript_name=req.transcript_name,
        category=req.category,
        eval_result=req.eval_result,
        fixture_dir=FIXTURE_DIR,
    )
    return SuggestionResponse(suggestions=suggestions)
