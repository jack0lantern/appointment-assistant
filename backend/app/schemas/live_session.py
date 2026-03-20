from datetime import datetime
from pydantic import BaseModel, Field


class LiveSessionCreate(BaseModel):
    """Request to start a new live therapy session."""
    session_date: datetime | None = None
    duration_minutes: int = 50


class LiveSessionToken(BaseModel):
    """Token response for joining a LiveKit room."""
    token: str
    room_name: str
    server_url: str
    peer_name: str = ""  # Name of the other participant (client for therapist, therapist for client)


class LiveSessionStatus(BaseModel):
    """Current status of a live session."""
    is_active: bool
    session_id: int
    room_name: str | None = None
    participants: list[dict] = Field(default_factory=list)
    duration_seconds: int = 0
    recording_status: str | None = None


class RecordingConsentRequest(BaseModel):
    """Request to give/revoke recording consent."""
    consented: bool


class RecordingConsentResponse(BaseModel):
    """Recording consent status."""
    session_id: int
    user_id: int
    consented: bool
    consented_at: datetime | None = None

    model_config = {"from_attributes": True}


class RecordingStatusResponse(BaseModel):
    """Current recording status for a session."""
    recording_status: str | None
    all_consented: bool
    consents: list[RecordingConsentResponse] = Field(default_factory=list)


class TranscriptPreview(BaseModel):
    """Preview of a diarized transcript before speaker confirmation."""
    session_id: int
    utterances: list[dict]
    speakers: list[str]  # unique speaker labels found
    duration_seconds: float


class SpeakerMapRequest(BaseModel):
    """Request to confirm speaker mapping for a diarized transcript."""
    speaker_map: dict[str, str]  # {"speaker_0": "therapist", "speaker_1": "client"}


class LiveSessionResponse(BaseModel):
    """Extended session response for live sessions."""
    id: int
    therapist_id: int
    client_id: int
    session_date: datetime | None = None
    session_number: int
    duration_minutes: int
    status: str
    session_type: str
    livekit_room_name: str | None = None
    recording_status: str | None = None

    model_config = {"from_attributes": True}
