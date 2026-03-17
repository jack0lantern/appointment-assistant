from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_therapist
from app.models.client import Client
from app.models.session import Session
from app.models.user import User
from app.schemas.client import ClientCreate, ClientResponse
from app.schemas.session import SessionResponse
from app.schemas.treatment_plan import TreatmentPlanResponse

router = APIRouter(prefix="/api/clients", tags=["clients"])


@router.get("", response_model=list[ClientResponse])
async def list_clients(
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
        select(Client).where(Client.therapist_id == therapist.id)
    )
    clients = result.scalars().all()
    return [ClientResponse.model_validate(c) for c in clients]


@router.post("", response_model=ClientResponse, status_code=status.HTTP_201_CREATED)
async def create_client(
    body: ClientCreate,
    therapist_user: User = Depends(require_therapist),
    db: AsyncSession = Depends(get_db),
):
    therapist = therapist_user.therapist_profile
    if therapist is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Therapist profile not found",
        )

    client = Client(
        therapist_id=therapist.id,
        name=body.name,
    )
    db.add(client)
    await db.commit()
    await db.refresh(client)
    return ClientResponse.model_validate(client)


@router.get("/{client_id}")
async def get_client(
    client_id: int,
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

    # Recent sessions (last 10)
    sess_result = await db.execute(
        select(Session)
        .where(Session.client_id == client_id)
        .order_by(Session.session_date.desc().nullslast(), Session.id.desc())
        .limit(10)
    )
    recent_sessions = sess_result.scalars().all()

    # Active treatment plan summary
    plan = client.treatment_plan
    plan_summary = None
    if plan is not None:
        plan_summary = TreatmentPlanResponse.model_validate(plan)

    return {
        "client": ClientResponse.model_validate(client),
        "recent_sessions": [SessionResponse.model_validate(s) for s in recent_sessions],
        "active_plan": plan_summary,
    }
