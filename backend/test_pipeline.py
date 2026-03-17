"""Manual test script for the AI pipeline.

Reads a transcript fixture, runs the full pipeline, and validates
that the output parses correctly into Pydantic schemas.

Requires ANTHROPIC_API_KEY to be set in the environment.

Usage:
    cd backend
    ANTHROPIC_API_KEY=sk-... python test_pipeline.py
"""

import asyncio
import json
import os
import sys

# Ensure the backend app is importable
sys.path.insert(0, os.path.dirname(__file__))

from app.schemas.ai_pipeline import PipelineResult
from app.schemas.treatment_plan import ClientPlanContent, TherapistPlanContent
from app.schemas.safety import SafetyFlagData
from app.services.ai_pipeline import preprocess_transcript, run_pipeline


FIXTURE_PATH = os.path.join(
    os.path.dirname(__file__), "evaluation", "fixtures", "anxiety.txt"
)


def print_section(title: str) -> None:
    print(f"\n{'=' * 60}")
    print(f"  {title}")
    print(f"{'=' * 60}")


async def main() -> None:
    # Check API key
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: ANTHROPIC_API_KEY environment variable is not set.")
        print("Usage: ANTHROPIC_API_KEY=sk-... python test_pipeline.py")
        sys.exit(1)

    # Load fixture
    if not os.path.exists(FIXTURE_PATH):
        print(f"ERROR: Fixture not found at {FIXTURE_PATH}")
        sys.exit(1)

    with open(FIXTURE_PATH, "r") as f:
        transcript_content = f.read()

    print(f"Loaded transcript: {len(transcript_content)} chars")

    # Test preprocessing
    print_section("PREPROCESSING")
    numbered, lines = preprocess_transcript(transcript_content)
    print(f"Lines: {len(lines)}")
    print(f"First 3 numbered lines:")
    for line in numbered.split("\n")[:3]:
        print(f"  {line}")

    # Run full pipeline
    print_section("RUNNING PIPELINE")
    print("Calling Claude API (this may take 15-30 seconds)...")

    result = await run_pipeline(
        transcript_content=transcript_content,
        preferences={"focus": "anxiety management", "modality": "CBT"},
    )

    # Validate result type
    print_section("VALIDATION")
    assert isinstance(result, PipelineResult), "Result is not a PipelineResult"
    print("[PASS] Result is a valid PipelineResult")

    assert isinstance(result.therapist_content, TherapistPlanContent)
    print("[PASS] therapist_content is valid TherapistPlanContent")

    assert isinstance(result.client_content, ClientPlanContent)
    print("[PASS] client_content is valid ClientPlanContent")

    for flag in result.safety_flags:
        assert isinstance(flag, SafetyFlagData)
    print(f"[PASS] {len(result.safety_flags)} safety flags are valid SafetyFlagData")

    # Print therapist content
    print_section("THERAPIST CONTENT")
    tc = result.therapist_content
    print(f"Presenting concerns ({len(tc.presenting_concerns)}):")
    for c in tc.presenting_concerns:
        print(f"  - {c}")
    print(f"Goals ({len(tc.goals)}):")
    for g in tc.goals:
        print(f"  - {g}")
    print(f"Interventions ({len(tc.interventions)}):")
    for i in tc.interventions:
        print(f"  - {i}")
    print(f"Homework ({len(tc.homework)}):")
    for h in tc.homework:
        print(f"  - {h}")
    print(f"Strengths ({len(tc.strengths)}):")
    for s in tc.strengths:
        print(f"  - {s}")
    print(f"Barriers ({len(tc.barriers)}):")
    for b in tc.barriers:
        print(f"  - {b}")
    print(f"Diagnosis considerations ({len(tc.diagnosis_considerations)}):")
    for d in tc.diagnosis_considerations:
        print(f"  - {d}")

    # Print citations sample
    print_section("CITATIONS (sample)")
    if tc.presenting_concerns_citations:
        cit = tc.presenting_concerns_citations[0]
        print(f"  Lines {cit.line_start}-{cit.line_end}: \"{cit.text}\"")

    # Print client content
    print_section("CLIENT CONTENT")
    cc = result.client_content
    print(f"What we talked about: {cc.what_we_talked_about}")
    print(f"Your goals ({len(cc.your_goals)}):")
    for g in cc.your_goals:
        print(f"  - {g}")
    print(f"Things to try ({len(cc.things_to_try)}):")
    for t in cc.things_to_try:
        print(f"  - {t}")
    print(f"Your strengths ({len(cc.your_strengths)}):")
    for s in cc.your_strengths:
        print(f"  - {s}")

    # Print summaries
    print_section("SESSION SUMMARIES")
    print(f"Therapist: {result.therapist_session_summary}")
    print(f"Client: {result.client_session_summary}")

    # Print metadata
    print_section("METADATA")
    print(f"Key themes: {result.key_themes}")
    print(f"Homework items: {result.homework_items}")
    print(f"Safety flags: {len(result.safety_flags)}")
    for flag in result.safety_flags:
        print(f"  [{flag.severity.value}] {flag.flag_type.value}: {flag.description}")
        print(f"    Lines {flag.line_start}-{flag.line_end}: \"{flag.transcript_excerpt[:80]}\"")
    print(f"AI metadata: {json.dumps(result.ai_metadata, indent=2)}")

    # Full JSON dump
    print_section("FULL JSON OUTPUT")
    print(json.dumps(result.model_dump(), indent=2, default=str))

    print_section("ALL TESTS PASSED")


if __name__ == "__main__":
    asyncio.run(main())
