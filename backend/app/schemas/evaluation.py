from pydantic import BaseModel


class StructuralValidationResult(BaseModel):
    valid: bool
    missing_fields: list[str] = []
    errors: list[str] = []


class ReadabilityResult(BaseModel):
    flesch_reading_ease: float
    flesch_kincaid_grade: float
    gunning_fog: float
    target_met: bool


class EvaluationRunResponse(BaseModel):
    structural: StructuralValidationResult
    readability: ReadabilityResult
    overall_pass: bool
