"""Prompt templates for generating therapist-facing treatment plan content."""

SYSTEM_PROMPT = """\
You are a clinical documentation assistant for licensed mental health therapists. \
Your role is to analyze therapy session transcripts and produce structured treatment \
plan content that is clinically accurate, evidence-based, and properly cited.

Rules:
- Every clinical observation MUST include a citation referencing the transcript line numbers.
- Citations use the format {"line_start": N, "line_end": M, "text": "quoted excerpt"}.
- The quoted text in citations should be a brief, relevant excerpt (one or two sentences max).
- Goals should be specific, measurable, and time-bound where possible.
- Interventions should reference evidence-based therapeutic modalities (CBT, DBT, ACT, etc.).
- Use professional clinical language appropriate for a therapist audience.
- If information is insufficient for a field, use "Insufficient data" rather than fabricating content.
- Be concise. Therapists must be able to scan this plan in under 2 minutes. Use short bullet phrases, not full sentences. Each item should be 10 words or fewer where possible.
- Homework MUST be limited to 1-2 key practices only. Choose the most impactful assignments.
- Respond ONLY with valid JSON matching the schema below. No markdown, no commentary."""

# Truncated few-shot example showing correct citation format
FEW_SHOT_EXAMPLE = """\
Example of correct output format (abbreviated):
{
  "presenting_concerns": [
    "Client reports persistent insomnia with difficulty falling asleep",
    "Elevated anxiety related to workplace performance"
  ],
  "presenting_concerns_citations": [
    {"line_start": 10, "line_end": 11, "text": "I can't sleep. I lie in bed and my mind just races"},
    {"line_start": 7, "line_end": 7, "text": "My manager keeps adding projects to my plate"}
  ],
  "goals": [
    {"description": "Reduce sleep onset latency to under 30 minutes", "timeframe": "4 weeks", "modality": "CBT-I"},
    {"description": "Develop cognitive restructuring skills for catastrophic thinking", "timeframe": "6 weeks", "modality": "CBT"}
  ],
  "goals_citations": [
    {"line_start": 10, "line_end": 11, "text": "I lie in bed and my mind just races"}
  ],
  "interventions": [
    {"name": "Thought Record", "modality": "CBT", "description": "Structured worksheet to identify and challenge automatic negative thoughts"},
    {"name": "Progressive Muscle Relaxation", "modality": "Behavioral", "description": "Systematic tensing and releasing of muscle groups to reduce physiological arousal"}
  ],
  "interventions_citations": [
    {"line_start": 57, "line_end": 57, "text": "I'd like you to try keeping a thought record"}
  ],
  "homework": [
    "Complete thought record at least once daily when anxiety spikes",
    "Practice progressive muscle relaxation before bed 3-4 times this week"
  ],
  "homework_citations": [
    {"line_start": 57, "line_end": 57, "text": "try keeping a thought record"}
  ],
  "strengths": [
    "Client demonstrates insight into irrational nature of catastrophic thoughts",
    "Client is motivated and willing to engage in homework assignments"
  ],
  "strengths_citations": [
    {"line_start": 19, "line_end": 19, "text": "I know it's irrational"}
  ],
  "barriers": [
    "High workplace demands limiting time for self-care",
    "Initial skepticism toward relaxation techniques"
  ],
  "barriers_citations": [
    {"line_start": 7, "line_end": 7, "text": "My manager keeps adding projects"},
    {"line_start": 67, "line_end": 67, "text": "I feel silly doing it and I don't think it works"}
  ],
  "diagnosis_considerations": [
    "Generalized Anxiety Disorder (F41.1) — rule out",
    "Panic Disorder (F41.0) — provisional, given reported panic-like episodes"
  ]
}"""

OUTPUT_SCHEMA = """\
Required JSON schema:
{
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
}"""


def build_user_prompt(
    numbered_transcript: str,
    therapist_preferences: dict | None = None,
    existing_plan: dict | None = None,
) -> str:
    """Build the user prompt for therapist plan generation.

    Args:
        numbered_transcript: The transcript with line numbers prepended.
        therapist_preferences: Optional dict of therapist style/focus preferences.
        existing_plan: Optional existing plan dict (for update mode).

    Returns:
        Formatted user prompt string.
    """
    parts: list[str] = []

    parts.append("Analyze the following therapy session transcript and generate "
                 "a structured treatment plan.\n")

    if therapist_preferences:
        pref_lines = []
        for key, value in therapist_preferences.items():
            pref_lines.append(f"- {key}: {value}")
        parts.append("Therapist preferences:\n" + "\n".join(pref_lines) + "\n")

    if existing_plan:
        parts.append(
            "An existing treatment plan is provided below. Use it as context to "
            "build upon, noting any progression or changes.\n"
            "EXISTING PLAN:\n"
            f"```json\n{_format_plan_json(existing_plan)}\n```\n"
        )

    parts.append(f"{OUTPUT_SCHEMA}\n")
    parts.append(f"{FEW_SHOT_EXAMPLE}\n")
    parts.append(f"SESSION TRANSCRIPT:\n{numbered_transcript}\n")
    parts.append("Respond with ONLY the JSON object. No markdown fences, no extra text.")

    return "\n".join(parts)


def _format_plan_json(plan: dict) -> str:
    """Format a plan dict as compact JSON for prompt inclusion."""
    import json
    return json.dumps(plan, indent=2, default=str)
