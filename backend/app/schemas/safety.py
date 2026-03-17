from enum import Enum
from datetime import datetime
from pydantic import BaseModel


class FlagType(str, Enum):
    suicidal_ideation = "suicidal_ideation"
    self_harm = "self_harm"
    harm_to_others = "harm_to_others"
    substance_crisis = "substance_crisis"
    severe_distress = "severe_distress"


class Severity(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"
    critical = "critical"


class SafetyFlagData(BaseModel):
    flag_type: FlagType
    severity: Severity
    description: str
    transcript_excerpt: str
    line_start: int
    line_end: int
    source: str = "regex"


class SafetyFlagResponse(BaseModel):
    id: int
    session_id: int | None = None
    treatment_plan_version_id: int | None = None
    flag_type: str
    severity: str
    description: str
    transcript_excerpt: str
    line_start: int | None = None
    line_end: int | None = None
    source: str
    acknowledged: bool
    acknowledged_at: datetime | None = None
    acknowledged_by: int | None = None

    model_config = {"from_attributes": True}
