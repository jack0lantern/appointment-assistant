"""Prompt templates for updating an existing treatment plan with a new session transcript."""

import json

SYSTEM_PROMPT = """\
You are a clinical documentation assistant for licensed mental health therapists. \
Your role is to UPDATE an existing treatment plan based on a new therapy session transcript. \

Rules:
- Review the existing plan and the new session transcript together.
- Preserve elements from the existing plan that remain relevant.
- Update goals, interventions, and homework based on progress or new information.
- Add new presenting concerns or barriers if they emerge in the new session.
- Remove or mark as completed any goals/homework that have been achieved.
- Every clinical observation MUST include a citation referencing the NEW transcript line numbers.
- Citations use the format {"line_start": N, "line_end": M, "text": "quoted excerpt"}.
- Generate a change_summary describing what was modified and why.
- Use professional clinical language appropriate for a therapist audience.
- Respond ONLY with valid JSON matching the schema below. No markdown, no commentary."""

OUTPUT_SCHEMA = """\
Required JSON schema:
{
  "therapist_content": {
    "presenting_concerns": ["string", ...],
    "presenting_concerns_citations": [{"line_start": int, "line_end": int, "text": "string"}, ...],
    "goals": [{"description": "string", "timeframe": "string", "modality": "string"}, ...],
    "goals_citations": [{"line_start": int, "line_end": int, "text": "string"}, ...],
    "interventions": [{"name": "string", "modality": "string", "description": "string"}, ...],
    "interventions_citations": [{"line_start": int, "line_end": int, "text": "string"}, ...],
    "homework": ["string", ...],
    "homework_citations": [{"line_start": int, "line_end": int, "text": "string"}, ...],
    "strengths": ["string", ...],
    "strengths_citations": [{"line_start": int, "line_end": int, "text": "string"}, ...],
    "barriers": ["string", ...],
    "barriers_citations": [{"line_start": int, "line_end": int, "text": "string"}, ...],
    "diagnosis_considerations": ["string", ...]
  },
  "change_summary": "string (2-4 sentences describing what changed from the previous plan and why)"
}"""


def build_user_prompt(
    numbered_transcript: str,
    existing_plan: dict,
    therapist_preferences: dict | None = None,
) -> str:
    """Build the user prompt for plan update generation.

    Args:
        numbered_transcript: The new session transcript with line numbers.
        existing_plan: The current treatment plan content dict.
        therapist_preferences: Optional dict of therapist style/focus preferences.

    Returns:
        Formatted user prompt string.
    """
    plan_json = json.dumps(existing_plan, indent=2, default=str)

    parts: list[str] = []

    parts.append(
        "Update the existing treatment plan based on the new therapy session transcript below. "
        "Preserve what is still relevant, update what has changed, and add anything new.\n"
    )

    if therapist_preferences:
        pref_lines = []
        for key, value in therapist_preferences.items():
            pref_lines.append(f"- {key}: {value}")
        parts.append("Therapist preferences:\n" + "\n".join(pref_lines) + "\n")

    parts.append(f"{OUTPUT_SCHEMA}\n")

    parts.append(f"EXISTING TREATMENT PLAN:\n```json\n{plan_json}\n```\n")
    parts.append(f"NEW SESSION TRANSCRIPT:\n{numbered_transcript}\n")
    parts.append("Respond with ONLY the JSON object. No markdown fences, no extra text.")

    return "\n".join(parts)
