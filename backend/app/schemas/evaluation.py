from __future__ import annotations
from datetime import datetime
from typing import Any
from pydantic import BaseModel


class ReadabilityScores(BaseModel):
    flesch_reading_ease: float
    flesch_kincaid_grade: float
    gunning_fog: float
    avg_sentence_length: float
    avg_word_length: float


class StructuralValidationResult(BaseModel):
    valid: bool
    missing_fields: list[str] = []
    errors: list[str] = []
    jargon_found: list[str] = []
    risk_data_found: bool = False
    citation_bounds_valid: bool = True


class ReadabilityResult(BaseModel):
    therapist_scores: ReadabilityScores
    client_scores: ReadabilityScores
    client_grade_ok: bool          # client FK grade <= 8
    separation_ok: bool             # therapist grade > client + 2
    flesch_reading_ease: float      # keep for backward compat
    flesch_kincaid_grade: float
    gunning_fog: float
    target_met: bool


class SafetyDetectionResult(BaseModel):
    transcript_name: str
    expected_flags: int
    detected_flags: int
    passed: bool


class TranscriptEvalResult(BaseModel):
    transcript_name: str
    structural: StructuralValidationResult
    readability: ReadabilityResult
    safety: SafetyDetectionResult | None = None
    generation_time_seconds: float
    # Plan content (optional — absent in old stored results)
    therapist_content: dict[str, Any] | None = None
    client_content: dict[str, Any] | None = None
    transcript_text: str | None = None
    safety_flags_detail: list[dict[str, Any]] | None = None


class EvaluationRunResponse(BaseModel):
    run_at: str
    results: list[TranscriptEvalResult]
    overall_pass: bool
    total_transcripts: int
    passed_structural: int
    passed_readability: int
    passed_safety: int
    # Keep these for backward compat
    structural: StructuralValidationResult | None = None
    readability: ReadabilityResult | None = None


class SuggestionRequest(BaseModel):
    transcript_name: str
    category: str  # "structural" | "readability" | "safety"
    eval_result: dict[str, Any]


class SuggestionResponse(BaseModel):
    suggestions: list[str]
