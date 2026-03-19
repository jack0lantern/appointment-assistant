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
- Respond ONLY with valid JSON matching the schema below. No markdown, no commentary.

Readability rules (IMPORTANT — client content MUST score at or below 8th-grade reading level):
1. Keep sentences short. Aim for 15 words or fewer per sentence. Break long \
sentences into two.
2. Use simple, everyday words. Replace clinical or multi-syllable words:
   - "utilize" → "use"
   - "demonstrate" → "show"
   - "emotional dysregulation" → "strong emotions that feel out of control"
   - "implement strategies" → "try these steps"
   - "in conjunction with" → "along with"
   - "modality" → "approach"
   - "psychoeducation" → "learning about how your mind works"
3. Use active voice. Say "Practice relaxation every day" not "Relaxation \
techniques should be practiced daily."
4. Use short bullet-style items instead of dense paragraphs. Break multi-step \
instructions into separate list items.
5. Limit "things_to_try" to 1-2 practices only — pick the most important one or two. \
Less is more; clients are more likely to follow through on fewer, focused assignments."""

OUTPUT_SCHEMA = """\
Required JSON schema:
{
  "client_content": {
    "what_we_talked_about": "string (2-4 sentences summarizing session themes in friendly language)",
    "your_goals": ["string (goal phrased as what the client is working toward)", ...],
    "things_to_try": ["string (1-2 homework practices max, phrased as invitations, not commands)", ...],
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
    "what_we_talked_about": "Today we talked about how work stress affects your sleep. We looked at thought patterns that keep you up at night. We also practiced a relaxation exercise together.",
    "your_goals": [
      "Sleep better by learning to quiet your mind at bedtime",
      "Handle anxious thoughts before they spiral"
    ],
    "things_to_try": [
      "Fill out a thought record once a day when you feel anxiety rising",
      "Practice the muscle relaxation exercise before bed 3-4 times this week"
    ],
    "your_strengths": [
      "You already notice when your worries are bigger than the situation",
      "You were open to trying new skills, even when they felt unfamiliar"
    ],
    "next_steps": [
      "Next session, we will look at your thought records together",
      "We will keep building on the relaxation skills you started today"
    ]
  },
  "client_session_summary": "Great work today! We talked about how work stress has hurt your sleep. We practiced some new tools to help. You are already showing a lot of self-awareness.",
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
