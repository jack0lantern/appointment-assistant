"""Tests for the emotional support module."""

import pytest

from app.services.emotional_support import (
    get_grounding_exercise,
    get_psychoeducation,
    get_validation_message,
    get_what_to_expect,
)


class TestGroundingExercises:
    def test_returns_string(self):
        result = get_grounding_exercise()
        assert isinstance(result, str)
        assert len(result) > 0

    def test_content_is_supportive(self):
        # Run multiple times to cover randomness
        for _ in range(10):
            result = get_grounding_exercise()
            # Should contain actionable guidance
            assert any(
                word in result.lower()
                for word in ["breathe", "feet", "see", "touch", "hear", "ground"]
            )


class TestValidationMessages:
    def test_returns_string(self):
        result = get_validation_message()
        assert isinstance(result, str)
        assert len(result) > 0

    def test_is_validating_tone(self):
        for _ in range(10):
            result = get_validation_message()
            # Should not contain invalidating language
            assert "you should" not in result.lower()
            assert "just" not in result.lower() or "just a" not in result.lower()


class TestPsychoeducation:
    def test_known_topic_returns_content(self):
        result = get_psychoeducation("anxiety")
        assert result is not None
        assert len(result) > 0

    def test_unknown_topic_returns_none(self):
        result = get_psychoeducation("nonexistent_topic")
        assert result is None

    def test_first_session_topic(self):
        result = get_psychoeducation("first_session")
        assert result is not None
        assert "session" in result.lower()


class TestWhatToExpect:
    def test_onboarding_content(self):
        result = get_what_to_expect("onboarding")
        assert result is not None
        assert "onboarding" in result.lower() or "information" in result.lower()

    def test_first_appointment_content(self):
        result = get_what_to_expect("first_appointment")
        assert result is not None
        assert "50 minutes" in result or "appointment" in result.lower()

    def test_unknown_context_returns_none(self):
        result = get_what_to_expect("unknown_context")
        assert result is None
