from pydantic import BaseModel
from app.schemas.ai_pipeline import PipelineResult


class TranscriptAnalysisRequest(BaseModel):
    transcript_text: str
    client_name: str = "Test Client"
    save: bool = True


class TranscriptAnalysisResponse(BaseModel):
    session_id: int | None
    treatment_plan_version_id: int | None
    pipeline_result: PipelineResult
    safety_flags_detected: int
    homework_items_created: int
    generation_time_seconds: float
