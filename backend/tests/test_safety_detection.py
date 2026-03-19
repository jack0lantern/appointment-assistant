import pytest
from app.utils.safety_patterns import scan_transcript_for_safety
from app.schemas.safety import FlagCategory


def _flag_types(flags):
    return [f.flag_type.value if hasattr(f.flag_type, 'value') else f.flag_type for f in flags]


def _safety_risk_flags(flags):
    return [f for f in flags if f.category == FlagCategory.safety_risk]


def _clinical_observation_flags(flags):
    return [f for f in flags if f.category == FlagCategory.clinical_observation]


def _clinician_omission_flags(flags):
    return [f for f in flags if f.category == FlagCategory.clinician_omission]


# ---------------------------------------------------------------------------
# Core safety risk detection (should still flag)
# ---------------------------------------------------------------------------


def test_suicidal_ideation_triggers_flag():
    lines = [
        "Therapist: How are you feeling?",
        "Client: I want to kill myself sometimes.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = _flag_types(_safety_risk_flags(flags))
    assert "suicidal_ideation" in flag_types


def test_self_harm_triggers_flag():
    lines = [
        "Therapist: Can you tell me more?",
        "Client: I've been cutting myself on my arms.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = _flag_types(_safety_risk_flags(flags))
    assert "self_harm" in flag_types


def test_harm_to_others_triggers_flag():
    lines = [
        "Therapist: What happened?",
        "Client: I want to hurt him so badly.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = _flag_types(_safety_risk_flags(flags))
    assert "harm_to_others" in flag_types


def test_substance_crisis_triggers_flag():
    lines = [
        "Therapist: Tell me about your drinking.",
        "Client: I blacked out from drinking last weekend.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = _flag_types(_safety_risk_flags(flags))
    assert "substance_crisis" in flag_types


def test_anger_does_not_trigger_flag():
    lines = [
        "Therapist: What happened with your husband?",
        "Client: I'm really angry at my husband.",
        "Therapist: Tell me more about that frustration.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    assert len(flags) == 0, f"False positive — anger should not flag: {flags}"


def test_si_with_treatment_context_still_flagged():
    """'Kill myself' should flag even when sentence references therapy/meeting."""
    lines = [
        "Client: I wanted to kill myself before this meeting.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    flag_types = _flag_types(flags)
    assert "suicidal_ideation" in flag_types


def test_historical_self_harm_triggers_flag():
    lines = [
        "Client: I used to self-harm but stopped years ago.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    # Historical mentions should still be flagged for therapist awareness
    assert len(flags) > 0


def test_deduplication_prevents_duplicate_flags():
    lines = [
        "Client: I sometimes think about suicide.",
    ]
    from app.schemas.safety import SafetyFlagData, FlagType, Severity
    existing_ai_flag = SafetyFlagData(
        flag_type=FlagType.suicidal_ideation,
        severity=Severity.high,
        description="Suicidal ideation mentioned",
        transcript_excerpt="I sometimes think about suicide",
        line_start=1,
        line_end=1,
        source="ai",
    )
    flags = scan_transcript_for_safety(lines, [existing_ai_flag])
    regex_flags = [f for f in flags if f.source == "regex" and f.flag_type == FlagType.suicidal_ideation]
    assert len(regex_flags) == 0


# ---------------------------------------------------------------------------
# Suggestion #1: Contextual disambiguation for hopelessness language
# ---------------------------------------------------------------------------


def test_treatment_directed_hopelessness_not_flagged():
    """'What's the point' about therapy should not trigger severe_distress."""
    lines = [
        "Client: What's the point. I don't know if this is helping.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    distress_flags = [f for f in flags if f.flag_type.value == "severe_distress"]
    assert len(distress_flags) == 0, (
        f"Treatment-directed hopelessness should not flag: {distress_flags}"
    )


def test_existential_hopelessness_with_incidental_treatment_mention():
    """Genuine distress should flag even when therapy is mentioned incidentally."""
    lines = [
        "Client: I feel hopeless, coming here doesn't change that nothing matters.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    distress_flags = [f for f in flags if f.flag_type.value == "severe_distress"]
    assert len(distress_flags) > 0, (
        "Existential hopelessness with incidental treatment mention should still flag"
    )


def test_existential_hopelessness_still_flagged():
    """Existential hopelessness without treatment context should still flag."""
    lines = [
        "Client: Nothing will ever get better. I feel hopeless.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    distress_flags = [f for f in flags if f.flag_type.value == "severe_distress"]
    assert len(distress_flags) > 0


# ---------------------------------------------------------------------------
# Suggestion #2: Separate symptom flags from safety flags
# ---------------------------------------------------------------------------


def test_depression_symptoms_are_clinical_observations():
    """Sleep, withdrawal, anhedonia should be clinical_observation, not safety_risk."""
    lines = [
        "Client: I sleep ten hours and still feel exhausted.",
        "Client: I stopped seeing my friends.",
        "Client: I don't enjoy anything anymore.",
        "Client: I've been skipping meals.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    safety_flags = _safety_risk_flags(flags)
    observation_flags = _clinical_observation_flags(flags)

    # No safety_risk flags from symptom patterns alone
    assert len(safety_flags) == 0, f"Symptoms should not be safety flags: {safety_flags}"
    # Should have clinical observations
    assert len(observation_flags) > 0


def test_symptoms_do_not_count_as_safety_risk():
    """Symptom-only transcript should pass safety detection (0 expected, 0 safety_risk)."""
    lines = [
        "Therapist: How have you been sleeping?",
        "Client: I sleep too much. Like eleven hours.",
        "Therapist: And your social life?",
        "Client: I stopped going out. I'm isolating.",
        "Therapist: Have you thought about hurting yourself?",
        "Client: No, nothing like that.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    safety_count = len(_safety_risk_flags(flags))
    assert safety_count == 0


# ---------------------------------------------------------------------------
# Suggestion #3: Multi-signal convergence for medium-severity flags
# ---------------------------------------------------------------------------


def test_single_medium_distress_signal_not_flagged():
    """A single medium-severity distress signal should not produce a safety flag."""
    lines = [
        "Client: I had a panic attack last night.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    medium_flags = [f for f in flags if f.severity.value == "medium"]
    assert len(medium_flags) == 0, (
        f"Single medium signal should not flag: {medium_flags}"
    )


def test_multiple_medium_distress_signals_flagged():
    """Multiple medium-severity distress signals should produce flags."""
    lines = [
        "Client: I had a panic attack and I feel like I'm dissociating.",
        "Client: I also can't breathe sometimes and don't feel real.",
    ]
    flags = _safety_risk_flags(scan_transcript_for_safety(lines, []))
    medium_flags = [f for f in flags if f.severity.value == "medium"]
    assert len(medium_flags) >= 2


# ---------------------------------------------------------------------------
# Suggestion #4: SI probe absence detector
# ---------------------------------------------------------------------------


def test_si_probe_absence_detected():
    """Multi-symptom depression without SI screen should flag clinician omission."""
    lines = [
        "Therapist: How have you been?",
        "Client: I sleep too much, maybe eleven hours a day.",
        "Client: I stopped seeing friends. I'm withdrawing from everyone.",
        "Client: I don't enjoy anything anymore. Not even basketball.",
        "Client: I've been skipping meals.",
        "Client: I can't focus at work at all.",
        "Therapist: Let's work on behavioral activation.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    omission_flags = _clinician_omission_flags(flags)
    assert len(omission_flags) == 1
    assert omission_flags[0].flag_type.value == "si_screen_absent"


def test_si_probe_present_no_omission_flag():
    """When therapist conducts SI screen, no clinician_omission flag."""
    lines = [
        "Therapist: How have you been?",
        "Client: I sleep too much, maybe eleven hours a day.",
        "Client: I stopped seeing friends. I'm withdrawing from everyone.",
        "Client: I don't enjoy anything anymore.",
        "Client: I've been skipping meals.",
        "Client: I can't focus at work.",
        "Therapist: Have you had any thoughts about hurting yourself?",
        "Client: No, nothing like that.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    omission_flags = _clinician_omission_flags(flags)
    assert len(omission_flags) == 0


# ---------------------------------------------------------------------------
# Integration: depression transcript should not produce false positive safety flags
# ---------------------------------------------------------------------------


def test_standard_depression_session_no_safety_risk_flags():
    """A standard depression assessment (like depression.txt) should produce
    zero safety_risk flags — only clinical observations and possibly
    a clinician omission."""
    lines = [
        "Therapist: How has your week been?",
        "Client: I almost didn't come. What's the point. I don't know if this is helping.",
        "Therapist: That feeling of what's the point — has that been showing up a lot lately?",
        "Client: I sleep ten, eleven hours and still feel exhausted.",
        "Client: I stopped playing basketball with my friends. Haven't gone in over a month.",
        "Client: My buddy texts me every Friday. Last week I didn't even respond.",
        "Client: Being around people takes so much energy. I feel like I'm bringing everyone down.",
        "Client: I used to like cooking. I haven't done that in weeks.",
        "Client: I stare at my screen for hours and barely get anything done.",
        "Therapist: Let's try behavioral activation this week.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    safety_flags = _safety_risk_flags(flags)
    assert len(safety_flags) == 0, (
        f"Standard depression session should not produce safety_risk flags: {safety_flags}"
    )
