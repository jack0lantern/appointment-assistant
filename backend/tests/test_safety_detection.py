import pytest
from app.utils.safety_patterns import scan_transcript_for_safety


def test_suicidal_ideation_triggers_flag():
    lines = [
        "Therapist: How are you feeling?",
        "Client: I want to kill myself sometimes.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = [f.flag_type.value if hasattr(f.flag_type, 'value') else f.flag_type for f in flags]
    assert "suicidal_ideation" in flag_types


def test_self_harm_triggers_flag():
    lines = [
        "Therapist: Can you tell me more?",
        "Client: I've been cutting myself on my arms.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = [f.flag_type.value if hasattr(f.flag_type, 'value') else f.flag_type for f in flags]
    assert "self_harm" in flag_types


def test_harm_to_others_triggers_flag():
    lines = [
        "Therapist: What happened?",
        "Client: I want to hurt him so badly.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = [f.flag_type.value if hasattr(f.flag_type, 'value') else f.flag_type for f in flags]
    assert "harm_to_others" in flag_types


def test_substance_crisis_triggers_flag():
    lines = [
        "Therapist: Tell me about your drinking.",
        "Client: I blacked out from drinking last weekend.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    flag_types = [f.flag_type.value if hasattr(f.flag_type, 'value') else f.flag_type for f in flags]
    assert "substance_crisis" in flag_types


def test_anger_does_not_trigger_flag():
    lines = [
        "Therapist: What happened with your husband?",
        "Client: I'm really angry at my husband.",
        "Therapist: Tell me more about that frustration.",
    ]
    flags = scan_transcript_for_safety(lines, [])
    assert len(flags) == 0, f"False positive — anger should not flag: {flags}"


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
    # Simulate an AI flag already covering this line range (1-indexed: line 1)
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
    # Should not create a duplicate since line range already covered
    regex_flags = [f for f in flags if f.source == "regex"]
    assert len(regex_flags) == 0
