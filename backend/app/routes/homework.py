from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db, require_client
from app.models.client import Client
from app.models.homework_item import HomeworkItem
from app.models.user import User
from app.schemas.homework import HomeworkItemResponse, HomeworkUpdateRequest

router = APIRouter(tags=["homework"])


@router.get("/api/my/homework", response_model=list[HomeworkItemResponse])
async def get_my_homework(
    client_user: User = Depends(require_client),
    db: AsyncSession = Depends(get_db),
):
    client = client_user.client_profile
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client profile not found")

    result = await db.execute(
        select(HomeworkItem)
        .where(
            HomeworkItem.client_id == client.id,
            HomeworkItem.completed == False,  # noqa: E712
        )
        .order_by(HomeworkItem.created_at.desc())
    )
    items = result.scalars().all()
    return [HomeworkItemResponse.model_validate(i) for i in items]


@router.patch("/api/homework/{item_id}", response_model=HomeworkItemResponse)
async def toggle_homework(
    item_id: int,
    body: HomeworkUpdateRequest,
    client_user: User = Depends(require_client),
    db: AsyncSession = Depends(get_db),
):
    client = client_user.client_profile
    if client is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Client profile not found")

    result = await db.execute(
        select(HomeworkItem).where(
            HomeworkItem.id == item_id,
            HomeworkItem.client_id == client.id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Homework item not found")

    item.completed = body.completed
    item.completed_at = datetime.utcnow() if body.completed else None
    await db.commit()
    await db.refresh(item)
    return HomeworkItemResponse.model_validate(item)
