from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.services.plan_service import compute_diff
from app.models.client import Client
from app.models.safety_flag import SafetyFlag
from app.models.session import Session
from app.models.treatment_plan import TreatmentPlan
from app.models.treatment_plan_version import TreatmentPlanVersion
from app.models.user import User
from app.schemas.safety import SafetyFlagResponse
from app.schemas.treatment_plan import (
    DiffResponse,
    PlanEditRequest,
    TreatmentPlanResponse,
    VersionResponse,
)

router = APIRouter(tags=["treatment_plans"])


# ── GET current plan for a client ────────────────────────────────────────────
@router.get(
    "/api/clients/{client_id}/treatment-plan",
)
async def get_current_plan(
    client_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Therapist profile not found")

    result = await db.execute(
        select(Client).where(
            Client.id == client_id,
            Client.therapist_id == therapist.id,
        )
    )
    client = result.scalar_one_or_none()
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client not found")

    plan = client.treatment_plan
    if plan is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No treatment plan found")

    latest_version = None
    if plan.current_version_id and plan.current_version:
        latest_version = VersionResponse.model_validate(plan.current_version)

    # Safety flags for the current version (or all client flags if no version)
    flag_result = await db.execute(
        select(SafetyFlag)
        .join(Session, SafetyFlag.session_id == Session.id)
        .where(Session.client_id == client_id)
        .order_by(SafetyFlag.created_at.desc())
    )
    safety_flags = flag_result.scalars().all()

    treatment_plan_data = TreatmentPlanResponse.model_validate(plan)
    response = {
        "treatment_plan": {
            **treatment_plan_data.model_dump(),
            "current_version": latest_version,
        },
        "safety_flags": [SafetyFlagResponse.model_validate(f) for f in safety_flags],
    }
    return response


# ── Version list ─────────────────────────────────────────────────────────────
@router.get(
    "/api/treatment-plans/{plan_id}/versions",
    response_model=list[VersionResponse],
)
async def list_versions(
    plan_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    plan = await _get_plan_for_therapist(plan_id, therapist_user, db)

    result = await db.execute(
        select(TreatmentPlanVersion)
        .where(TreatmentPlanVersion.treatment_plan_id == plan.id)
        .order_by(TreatmentPlanVersion.version_number.desc())
    )
    versions = result.scalars().all()
    return [VersionResponse.model_validate(v) for v in versions]


# ── Version detail ───────────────────────────────────────────────────────────
@router.get(
    "/api/treatment-plans/{plan_id}/versions/{version_id}",
    response_model=VersionResponse,
)
async def get_version(
    plan_id: int,
    version_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    await _get_plan_for_therapist(plan_id, therapist_user, db)

    result = await db.execute(
        select(TreatmentPlanVersion).where(
            TreatmentPlanVersion.id == version_id,
            TreatmentPlanVersion.treatment_plan_id == plan_id,
        )
    )
    version = result.scalar_one_or_none()
    if version is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Version not found")
    return VersionResponse.model_validate(version)


# ── Therapist edit (creates new version) ─────────────────────────────────────
@router.post(
    "/api/treatment-plans/{plan_id}/edit",
    response_model=VersionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def edit_plan(
    plan_id: int,
    body: PlanEditRequest,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    plan = await _get_plan_for_therapist(plan_id, therapist_user, db)

    # Determine next version number
    result = await db.execute(
        select(TreatmentPlanVersion)
        .where(TreatmentPlanVersion.treatment_plan_id == plan.id)
        .order_by(TreatmentPlanVersion.version_number.desc())
        .limit(1)
    )
    latest = result.scalar_one_or_none()
    next_number = (latest.version_number if latest else 0) + 1

    # Carry forward client_content from the latest version if available
    client_content = latest.client_content if latest else None

    new_version = TreatmentPlanVersion(
        treatment_plan_id=plan.id,
        version_number=next_number,
        session_id=latest.session_id if latest else None,
        therapist_content=body.therapist_content,
        client_content=client_content,
        change_summary=body.change_summary or "Therapist edit",
        source="therapist_edit",
    )
    db.add(new_version)
    await db.flush()

    plan.current_version_id = new_version.id
    plan.status = "draft"
    await db.commit()
    await db.refresh(new_version)
    return VersionResponse.model_validate(new_version)


# ── Approve plan ─────────────────────────────────────────────────────────────
@router.post(
    "/api/treatment-plans/{plan_id}/approve",
    response_model=TreatmentPlanResponse,
)
async def approve_plan(
    plan_id: int,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    plan = await _get_plan_for_therapist(plan_id, therapist_user, db)

    if plan.current_version_id is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="No version to approve",
        )

    # Check unacknowledged safety flags on the current version
    result = await db.execute(
        select(SafetyFlag).where(
            SafetyFlag.treatment_plan_version_id == plan.current_version_id,
            SafetyFlag.acknowledged == False,  # noqa: E712
        )
    )
    unack_flags = result.scalars().all()
    if unack_flags:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"{len(unack_flags)} unacknowledged safety flag(s) — acknowledge before approving",
        )

    plan.status = "approved"
    await db.commit()
    await db.refresh(plan)
    return TreatmentPlanResponse.model_validate(plan)


# ── Diff between two versions ────────────────────────────────────────────────
@router.get(
    "/api/treatment-plans/{plan_id}/diff",
    response_model=DiffResponse,
)
async def diff_versions(
    plan_id: int,
    v1: int = Query(..., description="First version number"),
    v2: int = Query(..., description="Second version number"),
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    plan = await _get_plan_for_therapist(plan_id, therapist_user, db)

    result1 = await db.execute(
        select(TreatmentPlanVersion).where(
            TreatmentPlanVersion.treatment_plan_id == plan.id,
            TreatmentPlanVersion.version_number == v1,
        )
    )
    ver1 = result1.scalar_one_or_none()

    result2 = await db.execute(
        select(TreatmentPlanVersion).where(
            TreatmentPlanVersion.treatment_plan_id == plan.id,
            TreatmentPlanVersion.version_number == v2,
        )
    )
    ver2 = result2.scalar_one_or_none()

    if ver1 is None or ver2 is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Version not found")

    diffs = compute_diff(ver1.therapist_content or {}, ver2.therapist_content or {})
    return DiffResponse(version_1=v1, version_2=v2, diffs=diffs)


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _get_plan_for_therapist(
    plan_id: int, therapist_user: User, db: AsyncSession
) -> TreatmentPlan:
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Therapist profile not found")

    result = await db.execute(
        select(TreatmentPlan).where(
            TreatmentPlan.id == plan_id,
            TreatmentPlan.therapist_id == therapist.id,
        )
    )
    plan = result.scalar_one_or_none()
    if plan is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Treatment plan not found")
    return plan
