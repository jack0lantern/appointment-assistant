import pytest
from pydantic import ValidationError
from app.schemas.treatment_plan import TherapistPlanContent, ClientPlanContent, Citation


def test_valid_therapist_content_parses(sample_therapist_content):
    plan = TherapistPlanContent(**sample_therapist_content)
    assert len(plan.presenting_concerns) == 2
    assert plan.goals[0]["description"] == "Reduce anxiety symptoms using CBT techniques"
    assert len(plan.interventions) == 1


def test_valid_client_content_parses(sample_client_content):
    plan = ClientPlanContent(**sample_client_content)
    assert plan.what_we_talked_about.startswith("We discussed")
    assert len(plan.your_goals) == 2
    assert len(plan.things_to_try) == 1


def test_malformed_therapist_content_raises_validation_error():
    with pytest.raises(ValidationError):
        # Missing all required fields
        TherapistPlanContent()


def test_extra_fields_ignored():
    # Extra fields should not cause errors (Pydantic v2 ignores by default)
    data = {
        "presenting_concerns": ["Test concern"],
        "goals": [],
        "interventions": [],
        "homework": [],
        "strengths": [],
        "unknown_extra_field": "should be ignored",
    }
    plan = TherapistPlanContent(**data)
    assert len(plan.presenting_concerns) == 1


def test_citation_parses_correctly():
    c = Citation(text="Client: I feel anxious", line_start=1, line_end=2)
    assert c.line_start == 1
    assert c.text == "Client: I feel anxious"


def test_realistic_ai_output_parses():
    realistic = {
        "presenting_concerns": [
            "Panic attacks at work occurring 3x/week with physical symptoms",
            "Avoidance behavior developing around meetings",
        ],
        "presenting_concerns_citations": [
            {"text": "My heart starts racing", "line_start": 3, "line_end": 4}
        ],
        "goals": [
            {"description": "Reduce panic attack frequency by 50%", "modality": "CBT", "timeframe": "8 weeks"},
            {"description": "Return to attending all work meetings", "modality": "Exposure therapy", "timeframe": "12 weeks"},
        ],
        "goals_citations": [],
        "interventions": [
            {"name": "Cognitive Restructuring", "modality": "CBT", "description": "Challenge catastrophic thinking"},
            {"name": "Interoceptive Exposure", "modality": "Behavioral", "description": "Gradual exposure to physical sensations"},
        ],
        "interventions_citations": [],
        "homework": [
            "Complete thought record worksheet when anxiety spikes",
            "Attend at least 2 meetings this week without leaving early",
        ],
        "homework_citations": [],
        "strengths": ["High motivation to change", "Good insight into triggers"],
        "strengths_citations": [],
    }
    plan = TherapistPlanContent(**realistic)
    assert len(plan.goals) == 2
    assert len(plan.interventions) == 2
    assert plan.presenting_concerns_citations[0].line_start == 3
