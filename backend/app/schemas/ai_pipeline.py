from pydantic import BaseModel
from app.schemas.treatment_plan import TherapistPlanContent, ClientPlanContent
from app.schemas.safety import SafetyFlagData


class PipelineResult(BaseModel):
    therapist_content: TherapistPlanContent
    client_content: ClientPlanContent
    therapist_session_summary: str
    client_session_summary: str
    key_themes: list[str]
    safety_flags: list[SafetyFlagData]
    homework_items: list[str]
    change_summary: str | None = None
    ai_metadata: dict
