"""AI pipeline service for generating structured treatment plans from transcripts.

Orchestrates: transcript preprocessing -> therapist plan generation (Claude) ->
client view generation (Claude) -> safety regex scanning -> final PipelineResult.
"""

import json
import logging
import os
import time
from typing import Any

import anthropic
from pydantic import ValidationError

from app.prompts import client_view, plan_update, therapist_plan
from app.schemas.ai_pipeline import PipelineResult
from app.schemas.safety import SafetyFlagData
from app.schemas.treatment_plan import ClientPlanContent, TherapistPlanContent
from app.utils.safety_patterns import scan_transcript_for_safety

logger = logging.getLogger(__name__)

MODEL = "claude-sonnet-4-6-20250514"
MAX_TOKENS = 4096


def _get_client() -> anthropic.AsyncAnthropic:
    """Create an Anthropic async client using the ANTHROPIC_API_KEY env var."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY environment variable is not set. "
            "Set it before running the AI pipeline."
        )
    return anthropic.AsyncAnthropic(api_key=api_key)


# ---------------------------------------------------------------------------
# Transcript preprocessing
# ---------------------------------------------------------------------------

def preprocess_transcript(content: str) -> tuple[str, list[str]]:
    """Split raw transcript content into numbered lines.

    Args:
        content: Raw transcript text.

    Returns:
        Tuple of (numbered_transcript_text, lines_list).
        - numbered_transcript_text: Each line prefixed with its 1-indexed number.
        - lines_list: The raw lines (for safety scanning).
    """
    raw_lines = content.split("\n")
    # Strip trailing empty lines but preserve internal blanks
    while raw_lines and raw_lines[-1].strip() == "":
        raw_lines.pop()

    numbered_parts: list[str] = []
    for idx, line in enumerate(raw_lines, start=1):
        numbered_parts.append(f"{idx}: {line}")

    numbered_text = "\n".join(numbered_parts)
    return numbered_text, raw_lines


# ---------------------------------------------------------------------------
# JSON parsing helpers
# ---------------------------------------------------------------------------

def _extract_json_from_text(text: str) -> str:
    """Extract JSON from Claude's response, stripping markdown fences if present."""
    cleaned = text.strip()

    # Strip markdown code fences
    if cleaned.startswith("```"):
        # Find the end of the opening fence line
        first_newline = cleaned.index("\n")
        # Find the closing fence
        last_fence = cleaned.rfind("```")
        if last_fence > first_newline:
            cleaned = cleaned[first_newline + 1 : last_fence].strip()
        else:
            cleaned = cleaned[first_newline + 1 :].strip()

    return cleaned


def _attempt_json_repair(text: str) -> str:
    """Attempt basic JSON repair for common issues."""
    cleaned = _extract_json_from_text(text)

    # Try to find the outermost JSON object
    brace_start = cleaned.find("{")
    brace_end = cleaned.rfind("}")
    if brace_start != -1 and brace_end != -1 and brace_end > brace_start:
        cleaned = cleaned[brace_start : brace_end + 1]

    # Remove trailing commas before closing braces/brackets
    cleaned = _remove_trailing_commas(cleaned)

    return cleaned


def _remove_trailing_commas(text: str) -> str:
    """Remove trailing commas before } or ] in JSON text."""
    import re
    # Remove comma followed by optional whitespace and then } or ]
    return re.sub(r",\s*([}\]])", r"\1", text)


def _fill_missing_fields(data: dict, schema_class: type) -> dict:
    """Fill missing required fields with defaults."""
    for field_name, field_info in schema_class.model_fields.items():
        if field_name not in data:
            if field_info.default is not None:
                data[field_name] = field_info.default
            elif hasattr(field_info.annotation, "__origin__"):
                # list types get empty list, str gets placeholder
                origin = getattr(field_info.annotation, "__origin__", None)
                if origin is list:
                    data[field_name] = []
                else:
                    data[field_name] = "Insufficient data"
            elif field_info.annotation is str:
                data[field_name] = "Insufficient data"
            else:
                data[field_name] = "Insufficient data"
    return data


# ---------------------------------------------------------------------------
# Claude API calls
# ---------------------------------------------------------------------------

async def generate_therapist_plan(
    transcript: str,
    preferences: dict | None = None,
    existing_plan: dict | None = None,
) -> TherapistPlanContent:
    """Generate therapist-facing treatment plan content via Claude.

    Args:
        transcript: Numbered transcript text.
        preferences: Optional therapist preferences dict.
        existing_plan: Optional existing plan for update mode.

    Returns:
        Validated TherapistPlanContent.

    Raises:
        RuntimeError: If generation fails after retry.
    """
    client = _get_client()

    user_prompt = therapist_plan.build_user_prompt(
        numbered_transcript=transcript,
        therapist_preferences=preferences,
        existing_plan=existing_plan,
    )

    last_error: Exception | None = None

    for attempt in range(2):  # Try up to 2 times
        try:
            response = await client.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                temperature=0.3,
                system=therapist_plan.SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_prompt}],
            )

            raw_text = response.content[0].text
            json_text = _extract_json_from_text(raw_text)

            try:
                data = json.loads(json_text)
            except json.JSONDecodeError:
                # Attempt repair
                repaired = _attempt_json_repair(raw_text)
                data = json.loads(repaired)

            # Fill missing fields before validation
            data = _fill_missing_fields(data, TherapistPlanContent)

            return TherapistPlanContent.model_validate(data)

        except ValidationError as e:
            logger.warning(
                "Therapist plan validation failed (attempt %d): %s",
                attempt + 1,
                str(e),
            )
            last_error = e
            if attempt == 0:
                # Retry with a hint about the validation error
                user_prompt += (
                    f"\n\nYour previous response had validation errors: {e}. "
                    "Please fix and respond with valid JSON only."
                )
                continue
            # On second failure, try to salvage what we can
            try:
                data = _fill_missing_fields(data, TherapistPlanContent)
                return TherapistPlanContent.model_validate(data)
            except Exception:
                pass

        except json.JSONDecodeError as e:
            logger.warning(
                "JSON decode failed (attempt %d): %s", attempt + 1, str(e)
            )
            last_error = e
            if attempt == 0:
                user_prompt += (
                    "\n\nYour previous response was not valid JSON. "
                    "Please respond with ONLY a valid JSON object."
                )
                continue

        except anthropic.APITimeoutError as e:
            logger.error("Anthropic API timeout: %s", str(e))
            raise RuntimeError(f"AI service timeout: {e}") from e

        except anthropic.APIError as e:
            logger.error("Anthropic API error: %s", str(e))
            raise RuntimeError(f"AI service error: {e}") from e

    raise RuntimeError(
        f"Failed to generate therapist plan after 2 attempts. Last error: {last_error}"
    )


async def generate_client_view(
    therapist_plan_data: dict,
) -> tuple[ClientPlanContent, str, str]:
    """Generate client-facing plan content and session summaries via Claude.

    Args:
        therapist_plan_data: The therapist plan content as a dict.

    Returns:
        Tuple of (ClientPlanContent, therapist_session_summary, client_session_summary).

    Raises:
        RuntimeError: If generation fails after retry.
    """
    client = _get_client()

    user_prompt = client_view.build_user_prompt(therapist_plan_data)

    last_error: Exception | None = None

    for attempt in range(2):
        try:
            response = await client.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                temperature=0.5,
                system=client_view.SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_prompt}],
            )

            raw_text = response.content[0].text
            json_text = _extract_json_from_text(raw_text)

            try:
                data = json.loads(json_text)
            except json.JSONDecodeError:
                repaired = _attempt_json_repair(raw_text)
                data = json.loads(repaired)

            # Extract sub-objects
            client_content_data = data.get("client_content", data)
            therapist_summary = data.get(
                "therapist_session_summary", "Insufficient data"
            )
            client_summary = data.get(
                "client_session_summary", "Insufficient data"
            )

            # Fill missing fields
            client_content_data = _fill_missing_fields(
                client_content_data, ClientPlanContent
            )

            client_content = ClientPlanContent.model_validate(client_content_data)
            return client_content, therapist_summary, client_summary

        except ValidationError as e:
            logger.warning(
                "Client view validation failed (attempt %d): %s",
                attempt + 1,
                str(e),
            )
            last_error = e
            if attempt == 0:
                user_prompt += (
                    f"\n\nYour previous response had validation errors: {e}. "
                    "Please fix and respond with valid JSON only."
                )
                continue

        except json.JSONDecodeError as e:
            logger.warning(
                "JSON decode failed (attempt %d): %s", attempt + 1, str(e)
            )
            last_error = e
            if attempt == 0:
                user_prompt += (
                    "\n\nYour previous response was not valid JSON. "
                    "Please respond with ONLY a valid JSON object."
                )
                continue

        except anthropic.APITimeoutError as e:
            logger.error("Anthropic API timeout: %s", str(e))
            raise RuntimeError(f"AI service timeout: {e}") from e

        except anthropic.APIError as e:
            logger.error("Anthropic API error: %s", str(e))
            raise RuntimeError(f"AI service error: {e}") from e

    raise RuntimeError(
        f"Failed to generate client view after 2 attempts. Last error: {last_error}"
    )


async def generate_plan_update(
    transcript: str,
    existing_plan: dict,
    preferences: dict | None = None,
) -> tuple[TherapistPlanContent, str]:
    """Generate an updated therapist plan based on a new session transcript.

    Args:
        transcript: Numbered transcript text for the new session.
        existing_plan: The current treatment plan content dict.
        preferences: Optional therapist preferences.

    Returns:
        Tuple of (updated TherapistPlanContent, change_summary string).

    Raises:
        RuntimeError: If generation fails after retry.
    """
    client = _get_client()

    user_prompt = plan_update.build_user_prompt(
        numbered_transcript=transcript,
        existing_plan=existing_plan,
        therapist_preferences=preferences,
    )

    last_error: Exception | None = None

    for attempt in range(2):
        try:
            response = await client.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                temperature=0.3,
                system=plan_update.SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_prompt}],
            )

            raw_text = response.content[0].text
            json_text = _extract_json_from_text(raw_text)

            try:
                data = json.loads(json_text)
            except json.JSONDecodeError:
                repaired = _attempt_json_repair(raw_text)
                data = json.loads(repaired)

            therapist_content_data = data.get("therapist_content", data)
            change_summary = data.get("change_summary", "Plan updated based on new session.")

            therapist_content_data = _fill_missing_fields(
                therapist_content_data, TherapistPlanContent
            )

            therapist_content = TherapistPlanContent.model_validate(therapist_content_data)
            return therapist_content, change_summary

        except ValidationError as e:
            logger.warning(
                "Plan update validation failed (attempt %d): %s",
                attempt + 1,
                str(e),
            )
            last_error = e
            if attempt == 0:
                user_prompt += (
                    f"\n\nYour previous response had validation errors: {e}. "
                    "Please fix and respond with valid JSON only."
                )
                continue

        except json.JSONDecodeError as e:
            logger.warning(
                "JSON decode failed (attempt %d): %s", attempt + 1, str(e)
            )
            last_error = e
            if attempt == 0:
                user_prompt += (
                    "\n\nYour previous response was not valid JSON. "
                    "Please respond with ONLY a valid JSON object."
                )
                continue

        except anthropic.APITimeoutError as e:
            logger.error("Anthropic API timeout: %s", str(e))
            raise RuntimeError(f"AI service timeout: {e}") from e

        except anthropic.APIError as e:
            logger.error("Anthropic API error: %s", str(e))
            raise RuntimeError(f"AI service error: {e}") from e

    raise RuntimeError(
        f"Failed to generate plan update after 2 attempts. Last error: {last_error}"
    )


# ---------------------------------------------------------------------------
# Key themes extraction
# ---------------------------------------------------------------------------

def _extract_key_themes(therapist_content: TherapistPlanContent) -> list[str]:
    """Extract key themes from the therapist plan content.

    Derives themes from presenting concerns, goals, and interventions
    without an additional API call.
    """
    themes: list[str] = []

    # Derive from presenting concerns (take first 3)
    for concern in therapist_content.presenting_concerns[:3]:
        # Truncate long concerns to a thematic phrase
        theme = concern.split(".")[0].strip()
        if theme and theme not in themes:
            themes.append(theme)

    # Derive from intervention modalities
    for intervention in therapist_content.interventions:
        modality = intervention.get("modality", "")
        if modality and modality not in themes:
            themes.append(modality)

    return themes[:5]  # Cap at 5 themes


# ---------------------------------------------------------------------------
# Main pipeline orchestrator
# ---------------------------------------------------------------------------

async def run_pipeline(
    transcript_content: str,
    preferences: dict | None = None,
    existing_plan: dict | None = None,
) -> PipelineResult:
    """Run the full AI treatment plan generation pipeline.

    Orchestrates:
    1. Preprocess transcript (number lines)
    2. Generate therapist plan via Claude (or update existing plan)
    3. Generate client view via Claude
    4. Scan transcript for safety flags via regex
    5. Assemble and return PipelineResult

    Args:
        transcript_content: Raw transcript text.
        preferences: Optional therapist preferences dict.
        existing_plan: Optional existing plan dict (triggers update mode).

    Returns:
        PipelineResult with all generated content and metadata.
    """
    start_time = time.time()

    # Step 1: Preprocess
    numbered_transcript, lines = preprocess_transcript(transcript_content)

    # Step 2: Generate therapist plan
    change_summary: str | None = None
    if existing_plan is not None:
        therapist_content, change_summary = await generate_plan_update(
            transcript=numbered_transcript,
            existing_plan=existing_plan,
            preferences=preferences,
        )
    else:
        therapist_content = await generate_therapist_plan(
            transcript=numbered_transcript,
            preferences=preferences,
            existing_plan=None,
        )

    # Step 3: Generate client view
    therapist_plan_dict = therapist_content.model_dump()
    client_content, therapist_summary, client_summary = await generate_client_view(
        therapist_plan_data=therapist_plan_dict,
    )

    # Step 4: Safety regex scan (no AI flags to deduplicate against for regex-only)
    safety_flags: list[SafetyFlagData] = scan_transcript_for_safety(
        lines=lines,
        existing_ai_flags=None,
    )

    # Step 5: Extract key themes and homework
    key_themes = _extract_key_themes(therapist_content)
    homework_items = list(therapist_content.homework)

    # Calculate metadata
    elapsed = time.time() - start_time
    ai_metadata = {
        "model": MODEL,
        "pipeline_duration_seconds": round(elapsed, 2),
        "transcript_lines": len(lines),
        "transcript_words": sum(len(line.split()) for line in lines),
        "safety_flags_found": len(safety_flags),
        "is_update": existing_plan is not None,
    }

    return PipelineResult(
        therapist_content=therapist_content,
        client_content=client_content,
        therapist_session_summary=therapist_summary,
        client_session_summary=client_summary,
        key_themes=key_themes,
        safety_flags=safety_flags,
        homework_items=homework_items,
        change_summary=change_summary,
        ai_metadata=ai_metadata,
    )
