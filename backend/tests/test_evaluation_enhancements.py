"""Tests for evaluation dashboard enhancements:
- Schema backward compatibility with new plan content fields
- Evaluation service preserving plan content
- Transcript text endpoint
- Suggestions endpoint
"""
import asyncio
import json
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path

from app.schemas.evaluation import (
    TranscriptEvalResult,
    StructuralValidationResult,
    ReadabilityResult,
    ReadabilityScores,
    SafetyDetectionResult,
    SuggestionRequest,
    SuggestionResponse,
)


def _dummy_readability_scores(**overrides):
    defaults = dict(
        flesch_reading_ease=60.0,
        flesch_kincaid_grade=8.0,
        gunning_fog=10.0,
        avg_sentence_length=15.0,
        avg_word_length=4.5,
    )
    defaults.update(overrides)
    return ReadabilityScores(**defaults)


def _dummy_readability_result(**overrides):
    defaults = dict(
        therapist_scores=_dummy_readability_scores(flesch_kincaid_grade=12.0),
        client_scores=_dummy_readability_scores(flesch_kincaid_grade=7.5),
        client_grade_ok=True,
        separation_ok=True,
        flesch_reading_ease=60.0,
        flesch_kincaid_grade=7.5,
        gunning_fog=10.0,
        target_met=True,
    )
    defaults.update(overrides)
    return ReadabilityResult(**defaults)


def _dummy_structural(**overrides):
    defaults = dict(valid=True)
    defaults.update(overrides)
    return StructuralValidationResult(**defaults)


# --- Schema backward compatibility tests ---


class TestSchemaBackwardCompat:
    def test_transcript_eval_result_without_plan_content(self):
        """Old results without plan content fields should deserialize fine."""
        result = TranscriptEvalResult(
            transcript_name="anxiety.txt",
            structural=_dummy_structural(),
            readability=_dummy_readability_result(),
            generation_time_seconds=2.5,
        )
        assert result.therapist_content is None
        assert result.client_content is None
        assert result.transcript_text is None
        assert result.safety_flags_detail is None

    def test_transcript_eval_result_with_plan_content(self):
        """New results with plan content should serialize/deserialize."""
        tc = {"presenting_concerns": ["Anxiety"], "goals": []}
        cc = {"what_we_talked_about": "We discussed anxiety."}
        flags = [{"flag_type": "suicidal_ideation", "severity": "high"}]

        result = TranscriptEvalResult(
            transcript_name="crisis.txt",
            structural=_dummy_structural(),
            readability=_dummy_readability_result(),
            generation_time_seconds=3.1,
            therapist_content=tc,
            client_content=cc,
            transcript_text="Therapist: Hello\nClient: Hi",
            safety_flags_detail=flags,
        )
        assert result.therapist_content == tc
        assert result.client_content == cc
        assert result.transcript_text == "Therapist: Hello\nClient: Hi"
        assert result.safety_flags_detail == flags

    def test_roundtrip_serialization(self):
        """Results should survive JSON roundtrip (simulating DB JSONB storage)."""
        result = TranscriptEvalResult(
            transcript_name="test.txt",
            structural=_dummy_structural(),
            readability=_dummy_readability_result(),
            generation_time_seconds=1.0,
            therapist_content={"goals": ["reduce anxiety"]},
            client_content={"your_goals": ["feel better"]},
            transcript_text="line 1\nline 2",
        )
        dumped = result.model_dump()
        restored = TranscriptEvalResult(**dumped)
        assert restored.therapist_content == {"goals": ["reduce anxiety"]}
        assert restored.transcript_text == "line 1\nline 2"


class TestSuggestionSchemas:
    def test_suggestion_request_valid(self):
        req = SuggestionRequest(
            transcript_name="anxiety.txt",
            category="structural",
            eval_result={"valid": False, "jargon_found": ["CBT"]},
        )
        assert req.category == "structural"

    def test_suggestion_response(self):
        resp = SuggestionResponse(suggestions=["Replace 'CBT' with 'talk therapy'"])
        assert len(resp.suggestions) == 1


# --- Evaluation service tests ---


class TestEvalServicePreservesContent:
    @pytest.mark.asyncio
    async def test_run_evaluation_includes_plan_content(
        self, sample_therapist_content, sample_client_content, tmp_path
    ):
        """run_evaluation should include therapist/client content in results."""
        from app.schemas.treatment_plan import TherapistPlanContent, ClientPlanContent
        from app.schemas.ai_pipeline import PipelineResult

        # Create a fixture file
        fixture_file = tmp_path / "test_transcript.txt"
        fixture_file.write_text("Therapist: Hello\nClient: Hi there")

        mock_pipeline_result = PipelineResult(
            therapist_content=TherapistPlanContent(**sample_therapist_content),
            client_content=ClientPlanContent(**sample_client_content),
            therapist_session_summary="Summary for therapist",
            client_session_summary="Summary for client",
            key_themes=["anxiety"],
            safety_flags=[],
            homework_items=["breathing exercises"],
            ai_metadata={"model": "test", "duration_seconds": 1.0},
        )

        with patch(
            "app.services.ai_pipeline.run_pipeline",
            new_callable=AsyncMock,
            return_value=mock_pipeline_result,
        ):
            from app.services.evaluation_service import run_evaluation

            result = await run_evaluation(str(tmp_path))

        assert len(result.results) == 1
        r = result.results[0]
        assert r.therapist_content is not None
        assert r.client_content is not None
        assert r.transcript_text == "Therapist: Hello\nClient: Hi there"
        assert r.therapist_content["presenting_concerns"] == sample_therapist_content["presenting_concerns"]


# --- Endpoint tests ---


class TestTranscriptEndpoint:
    @pytest.mark.asyncio
    async def test_get_transcript_returns_text(self):
        """GET /api/evaluation/transcripts/{name} should return fixture text."""
        from app.routes.evaluation import get_transcript_text, FIXTURE_DIR

        fixture_path = Path(FIXTURE_DIR)
        # Use an actual fixture file
        if (fixture_path / "anxiety.txt").exists():
            response = await get_transcript_text("anxiety.txt")
            assert isinstance(response.body, bytes)
            text = response.body.decode()
            assert "Therapist" in text or "Client" in text

    @pytest.mark.asyncio
    async def test_get_transcript_rejects_path_traversal(self):
        """Should reject names with path traversal."""
        from fastapi import HTTPException
        from app.routes.evaluation import get_transcript_text

        with pytest.raises(HTTPException) as exc_info:
            await get_transcript_text("../../../etc/passwd")
        assert exc_info.value.status_code == 400

    @pytest.mark.asyncio
    async def test_get_transcript_404_for_missing(self):
        """Should return 404 for non-existent file."""
        from fastapi import HTTPException
        from app.routes.evaluation import get_transcript_text

        with pytest.raises(HTTPException) as exc_info:
            await get_transcript_text("nonexistent.txt")
        assert exc_info.value.status_code == 404


# --- Streaming and cancellation tests ---


class TestEvaluationStreamingAndCancel:
    @pytest.mark.asyncio
    async def test_run_evaluation_stream_yields_results(self, tmp_path):
        """run_evaluation_stream should yield (result, index, total) for each transcript."""
        from app.services.evaluation_service import run_evaluation_stream
        from app.schemas.treatment_plan import TherapistPlanContent, ClientPlanContent
        from app.schemas.ai_pipeline import PipelineResult

        # Create two fixture files
        (tmp_path / "first.txt").write_text("Therapist: Hello\nClient: Hi")
        (tmp_path / "second.txt").write_text("Therapist: How are you?\nClient: Good")

        mock_result = PipelineResult(
            therapist_content=TherapistPlanContent(
                presenting_concerns=["Test"],
                goals=[],
                interventions=[],
                homework=[],
                strengths=[],
            ),
            client_content=ClientPlanContent(
                what_we_talked_about="Test",
                your_goals=[],
                things_to_try=[],
                your_strengths=[],
            ),
            therapist_session_summary="Summary",
            client_session_summary="Client summary",
            key_themes=["test"],
            safety_flags=[],
            homework_items=[],
            ai_metadata={"model": "test", "duration_seconds": 1.0},
        )

        with patch(
            "app.services.ai_pipeline.run_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            cancel_event = asyncio.Event()
            results = []
            async for result, idx, total in run_evaluation_stream(str(tmp_path), cancel_event):
                results.append((result.transcript_name, idx, total))

        assert len(results) == 2
        # idx is 1-based (completed count)
        names = {r[0] for r in results}
        assert names == {"first.txt", "second.txt"}
        idxs = [r[1] for r in results]
        assert sorted(idxs) == [1, 2]
        assert all(r[2] == 2 for r in results)

    @pytest.mark.asyncio
    async def test_run_evaluation_stream_respects_cancel_event(self, tmp_path):
        """Generator should stop when cancel_event is set between transcripts."""
        from app.services.evaluation_service import run_evaluation_stream
        from app.schemas.treatment_plan import TherapistPlanContent, ClientPlanContent
        from app.schemas.ai_pipeline import PipelineResult

        # Create three fixture files
        for i in range(3):
            (tmp_path / f"transcript_{i}.txt").write_text(f"Content {i}")

        mock_result = PipelineResult(
            therapist_content=TherapistPlanContent(
                presenting_concerns=["Test"],
                goals=[],
                interventions=[],
                homework=[],
                strengths=[],
            ),
            client_content=ClientPlanContent(
                what_we_talked_about="Test",
                your_goals=[],
                things_to_try=[],
                your_strengths=[],
            ),
            therapist_session_summary="Summary",
            client_session_summary="Client summary",
            key_themes=["test"],
            safety_flags=[],
            homework_items=[],
            ai_metadata={"model": "test", "duration_seconds": 1.0},
        )

        call_count = 0
        async def mock_run_pipeline(text):
            nonlocal call_count
            call_count += 1
            # Stagger completion so first finishes before others; cancel can then stop the rest
            await asyncio.sleep(0.1 * call_count)
            return mock_result

        with patch(
            "app.services.ai_pipeline.run_pipeline",
            side_effect=mock_run_pipeline,
        ):
            cancel_event = asyncio.Event()
            results = []
            async for result, idx, total in run_evaluation_stream(str(tmp_path), cancel_event):
                results.append(result.transcript_name)
                if idx == 1:  # After first transcript, set cancel
                    cancel_event.set()

        # Should have processed 1 transcript and then stopped (others cancelled)
        assert len(results) == 1
        assert call_count >= 1

    @pytest.mark.asyncio
    async def test_run_evaluation_backward_compat(self, tmp_path):
        """run_evaluation (old API) should still work for backward compat."""
        from app.services.evaluation_service import run_evaluation
        from app.schemas.treatment_plan import TherapistPlanContent, ClientPlanContent
        from app.schemas.ai_pipeline import PipelineResult

        (tmp_path / "test.txt").write_text("Therapist: Hi\nClient: Hello")

        mock_result = PipelineResult(
            therapist_content=TherapistPlanContent(
                presenting_concerns=["Test"],
                goals=[],
                interventions=[],
                homework=[],
                strengths=[],
            ),
            client_content=ClientPlanContent(
                what_we_talked_about="Test",
                your_goals=[],
                things_to_try=[],
                your_strengths=[],
            ),
            therapist_session_summary="Summary",
            client_session_summary="Client summary",
            key_themes=["test"],
            safety_flags=[],
            homework_items=[],
            ai_metadata={"model": "test", "duration_seconds": 1.0},
        )

        with patch(
            "app.services.ai_pipeline.run_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            result = await run_evaluation(str(tmp_path))

        assert result.total_transcripts == 1
        assert len(result.results) == 1
