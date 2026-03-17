from datetime import datetime
from pydantic import BaseModel


class HomeworkItemResponse(BaseModel):
    id: int
    treatment_plan_version_id: int
    client_id: int
    description: str
    completed: bool
    completed_at: datetime | None = None

    model_config = {"from_attributes": True}


class HomeworkUpdateRequest(BaseModel):
    completed: bool
