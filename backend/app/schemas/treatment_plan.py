from datetime import datetime
from pydantic import BaseModel


class Citation(BaseModel):
    line_start: int
    line_end: int
    text: str


class TherapistPlanContent(BaseModel):
    presenting_concerns: list[str]
    presenting_concerns_citations: list[Citation] = []
    goals: list[dict]
    goals_citations: list[Citation] = []
    interventions: list[dict]
    interventions_citations: list[Citation] = []
    homework: list[str]
    homework_citations: list[Citation] = []
    strengths: list[str]
    strengths_citations: list[Citation] = []
    barriers: list[str] = []
    barriers_citations: list[Citation] = []
    diagnosis_considerations: list[str] = []


class ClientPlanContent(BaseModel):
    what_we_talked_about: str
    your_goals: list[str]
    things_to_try: list[str]
    your_strengths: list[str]
    next_steps: list[str] = []


class TreatmentPlanResponse(BaseModel):
    id: int
    client_id: int
    therapist_id: int
    current_version_id: int | None = None
    status: str

    model_config = {"from_attributes": True}


class VersionResponse(BaseModel):
    id: int
    treatment_plan_id: int
    version_number: int
    session_id: int | None = None
    therapist_content: dict | None = None
    client_content: dict | None = None
    change_summary: str | None = None
    source: str
    ai_metadata: dict | None = None
    created_at: datetime | None = None

    model_config = {"from_attributes": True}


class PlanEditRequest(BaseModel):
    therapist_content: dict
    change_summary: str | None = None


class DiffResponse(BaseModel):
    version_1: int
    version_2: int
    diffs: dict
