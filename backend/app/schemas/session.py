from datetime import date, datetime
from pydantic import BaseModel


class SessionCreate(BaseModel):
    transcript_text: str
    session_date: date | None = None
    duration_minutes: int = 50


class SessionResponse(BaseModel):
    id: int
    therapist_id: int
    client_id: int
    session_date: datetime | None = None
    session_number: int
    duration_minutes: int
    status: str

    model_config = {"from_attributes": True}


class TranscriptResponse(BaseModel):
    id: int
    session_id: int
    content: str
    source_type: str
    word_count: int

    model_config = {"from_attributes": True}
