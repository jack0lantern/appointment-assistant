import pytest


@pytest.fixture
def sample_transcript_lines():
    return [
        "Therapist: How have you been feeling this week?",
        "Client: Pretty anxious. Cannot sleep and my mind keeps racing.",
        "Therapist: Tell me more about what triggers the anxiety.",
        "Client: Work deadlines mostly. I keep thinking I'm going to fail.",
        "Therapist: Those are cognitive distortions we can work on together.",
        "Client: I also have trouble concentrating during the day.",
        "Therapist: Have you tried any of the breathing exercises we discussed?",
        "Client: Yes, they help a little but the thoughts keep coming back.",
    ]


@pytest.fixture
def sample_therapist_content():
    return {
        "presenting_concerns": [
            "Generalized anxiety with sleep disturbance and racing thoughts",
            "Work-related cognitive distortions including catastrophizing",
        ],
        "presenting_concerns_citations": [
            {"text": "Cannot sleep and my mind keeps racing", "line_start": 1, "line_end": 2},
        ],
        "goals": [
            {"description": "Reduce anxiety symptoms using CBT techniques", "modality": "CBT", "timeframe": "4 weeks"},
        ],
        "goals_citations": [],
        "interventions": [
            {"name": "Cognitive Restructuring", "modality": "CBT", "description": "Challenge cognitive distortions around work performance"},
        ],
        "interventions_citations": [],
        "homework": ["Practice 4-7-8 breathing daily for 10 minutes"],
        "homework_citations": [],
        "strengths": ["Self-aware about anxiety patterns", "Motivated to engage in therapy"],
        "strengths_citations": [],
        "barriers": [],
        "diagnosis_considerations": [],
    }


@pytest.fixture
def sample_client_content():
    return {
        "what_we_talked_about": "We discussed the anxiety and racing thoughts you've been experiencing, especially around work.",
        "your_goals": [
            "Feel less overwhelmed by work deadlines",
            "Sleep better at night with a calmer mind",
        ],
        "things_to_try": ["Practice breathing exercises for 10 minutes each day"],
        "your_strengths": ["You recognize your patterns and want to make changes"],
        "next_steps": ["Keep a brief daily journal of anxious thoughts"],
    }
