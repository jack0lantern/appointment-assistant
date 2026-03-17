import pytest
from app.services.evaluation_service import validate_plan_structure


def test_valid_plan_passes_validation(sample_therapist_content, sample_client_content, sample_transcript_lines):
    result = validate_plan_structure(sample_therapist_content, sample_client_content, sample_transcript_lines)
    assert result.valid is True
    assert result.missing_fields == []
    assert result.jargon_found == []
    assert result.risk_data_found is False


def test_citation_out_of_bounds_fails(sample_client_content, sample_transcript_lines):
    bad_content = {
        "presenting_concerns": ["Anxiety"],
        "presenting_concerns_citations": [
            {"text": "out of bounds", "line_start": 0, "line_end": 9999}
        ],
        "goals": [{"description": "Goal", "modality": "CBT", "timeframe": "4 weeks"}],
        "goals_citations": [],
        "interventions": [{"name": "CBT", "modality": "CBT", "description": "desc"}],
        "interventions_citations": [],
        "homework": ["Do something"],
        "homework_citations": [],
        "strengths": ["Strong"],
        "strengths_citations": [],
    }
    result = validate_plan_structure(bad_content, sample_client_content, sample_transcript_lines)
    assert result.citation_bounds_valid is False


def test_clinical_jargon_fails(sample_therapist_content, sample_transcript_lines):
    jargon_client_content = {
        "what_we_talked_about": "We discussed your F41.1 diagnosis and ICD codes.",
        "your_goals": ["Manage DSM criteria"],
        "things_to_try": [],
        "your_strengths": [],
        "next_steps": [],
    }
    result = validate_plan_structure(sample_therapist_content, jargon_client_content, sample_transcript_lines)
    assert result.valid is False
    assert len(result.jargon_found) > 0


def test_risk_data_in_client_content_fails(sample_therapist_content, sample_transcript_lines):
    risk_client_content = {
        "what_we_talked_about": "We discussed your suicidal thoughts.",
        "your_goals": ["Stay safe"],
        "things_to_try": [],
        "your_strengths": [],
        "next_steps": [],
    }
    result = validate_plan_structure(sample_therapist_content, risk_client_content, sample_transcript_lines)
    assert result.risk_data_found is True
    assert result.valid is False
