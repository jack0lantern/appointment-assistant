"""Prompt templates for generating client-facing treatment plan content."""

import json

SYSTEM_PROMPT = """\
You are a compassionate health communication specialist who translates clinical \
mental health treatment plans into warm, accessible language for clients. \

Rules:
- Use second person ("you") to speak directly to the client.
- Avoid clinical jargon; use plain, encouraging language at an 8th-grade reading level.
- Be warm and validating without being patronizing.
- Frame everything constructively — focus on growth, not deficits.
- Do not include diagnosis information in client-facing content.
- Generate both a client-friendly plan AND a brief session summary for the client.
- Also generate a therapist-facing session summary (concise, clinical language).
- Respond ONLY with valid JSON matching the schema below. No markdown, no commentary."""

OUTPUT_SCHEMA = """\
Required JSON schema:
{
  "client_content": {
    "what_we_talked_about": "string (2-4 sentences summarizing session themes in friendly language)",
    "your_goals": ["string (goal phrased as what the client is working toward)", ...],
    "things_to_try": ["string (homework/exercises phrased as invitations, not commands)", ...],
    "your_strengths": ["string (observed strengths phrased positively)", ...],
    "next_steps": ["string (what to expect going forward)", ...]
  },
  "client_session_summary": "string (2-3 sentences, warm and encouraging summary for the client)",
  "therapist_session_summary": "string (2-3 sentences, concise clinical summary for the therapist)"
}"""

FEW_SHOT_EXAMPLE = """\
Example of correct output format (abbreviated):
{
  "client_content": {
    "what_we_talked_about": "Today we explored how work stress has been affecting your sleep and overall well-being. We looked at some of the thought patterns that keep you up at night and practiced a relaxation technique together.",
    "your_goals": [
      "Getting better sleep by learning to quiet your mind at bedtime",
      "Building skills to manage anxious thoughts when they spiral"
    ],
    "things_to_try": [
      "Try filling out a thought record once a day when you notice anxiety rising — there is a template to help guide you",
      "Practice the muscle relaxation exercise we did today before bed, aiming for 3-4 times this week"
    ],
    "your_strengths": [
      "You are already noticing when your worries are bigger than the situation calls for — that is a really valuable skill",
      "You showed openness to trying new techniques even when they felt unfamiliar"
    ],
    "next_steps": [
      "We will review your thought records together next session",
      "We will continue building on the relaxation skills you started today"
    ]
  },
  "client_session_summary": "Great work today! We talked about how work stress has been causing sleep difficulties and practiced some new tools to help. You are already showing a lot of self-awareness, which is a great foundation.",
  "therapist_session_summary": "Session focused on work-related anxiety and insomnia. Introduced cognitive restructuring via thought records and PMR for sleep hygiene. Client demonstrated good insight into catastrophizing patterns. Homework: daily thought record, PMR 3-4x/week."
}"""


def build_user_prompt(therapist_plan: dict) -> str:
    """Build the user prompt for client view generation.

    Args:
        therapist_plan: The therapist-facing plan content dict.

    Returns:
        Formatted user prompt string.
    """
    plan_json = json.dumps(therapist_plan, indent=2, default=str)

    return (
        "Transform the following therapist treatment plan into client-friendly content. "
        "Also generate a brief session summary for both the client and therapist.\n\n"
        f"{OUTPUT_SCHEMA}\n\n"
        f"{FEW_SHOT_EXAMPLE}\n\n"
        f"THERAPIST PLAN:\n```json\n{plan_json}\n```\n\n"
        "Respond with ONLY the JSON object. No markdown fences, no extra text."
    )
