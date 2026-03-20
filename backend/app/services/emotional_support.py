"""Emotional support content module.

Provides brief, evidence-informed supportive snippets and psychoeducation
for key moments in the user journey. Invoked by the agent service when
emotional support context is detected.
"""

from __future__ import annotations

import random


# ── Grounding exercises ──────────────────────────────────────────────────────

GROUNDING_EXERCISES: list[str] = [
    (
        "Let's try a quick grounding exercise. Look around and name:\n"
        "- **5** things you can see\n"
        "- **4** things you can touch\n"
        "- **3** things you can hear\n"
        "- **2** things you can smell\n"
        "- **1** thing you can taste\n\n"
        "Take your time with each one."
    ),
    (
        "Here's a simple breathing exercise:\n"
        "1. Breathe in slowly for **4 counts**\n"
        "2. Hold for **4 counts**\n"
        "3. Breathe out slowly for **6 counts**\n"
        "4. Repeat 3-4 times\n\n"
        "This helps activate your body's natural calm response."
    ),
    (
        "Try placing both feet flat on the floor. Press them down gently and "
        "notice the sensation of being grounded. Take three slow breaths, "
        "focusing on the feeling of your feet connecting with the ground."
    ),
]

# ── Validating messages ──────────────────────────────────────────────────────

VALIDATION_MESSAGES: list[str] = [
    "What you're feeling is completely valid. It takes courage to reach out, and you've already taken that step.",
    "It's okay to feel this way. Many people experience similar feelings, and you don't have to face them alone.",
    "Thank you for sharing that with me. Your feelings matter, and it's important to acknowledge them.",
    "Starting therapy can bring up a lot of emotions — that's completely normal and actually a sign of strength.",
]

# ── Psychoeducation snippets ─────────────────────────────────────────────────

PSYCHOEDUCATION: dict[str, list[str]] = {
    "anxiety": [
        "Anxiety is your brain's way of trying to protect you. While it can feel overwhelming, "
        "it's a natural response that can be managed with the right tools and support.",
        "Many people find that anxiety decreases once they begin working with a therapist. "
        "You don't have to have it all figured out before your first session.",
    ],
    "first_session": [
        "Your first session is mostly about getting to know your therapist. There's no wrong "
        "way to start — you can share as much or as little as you're comfortable with.",
        "It's normal to feel nervous before a first session. Your therapist is trained to "
        "help you feel at ease, and everything you share is confidential.",
    ],
    "therapy_general": [
        "Therapy is a collaborative process. You and your therapist work together to "
        "understand your experiences and develop strategies that work for you.",
        "Progress in therapy isn't always linear — some weeks feel easier than others. "
        "That's completely normal and part of the process.",
    ],
}

# ── What-to-expect content ───────────────────────────────────────────────────

WHAT_TO_EXPECT: dict[str, str] = {
    "onboarding": (
        "Here's what to expect during onboarding:\n"
        "1. **Basic information** — We'll collect some general details to match you with the right therapist\n"
        "2. **Insurance verification** — If applicable, we'll help verify your coverage\n"
        "3. **Scheduling** — We'll find a time that works for you\n\n"
        "The whole process typically takes about 10-15 minutes."
    ),
    "first_appointment": (
        "Here's what to expect for your first appointment:\n"
        "- It usually lasts about **50 minutes**\n"
        "- Your therapist will ask about what brings you to therapy\n"
        "- You can share at your own pace — there's no pressure\n"
        "- Together, you'll start to outline goals for your work\n\n"
        "Remember: there are no wrong answers."
    ),
}


def get_grounding_exercise() -> str:
    """Return a random grounding exercise."""
    return random.choice(GROUNDING_EXERCISES)


def get_validation_message() -> str:
    """Return a random validating message."""
    return random.choice(VALIDATION_MESSAGES)


def get_psychoeducation(topic: str) -> str | None:
    """Return a psychoeducation snippet for a topic, or None if unknown."""
    snippets = PSYCHOEDUCATION.get(topic)
    if snippets:
        return random.choice(snippets)
    return None


def get_what_to_expect(context: str) -> str | None:
    """Return what-to-expect content for a given context."""
    return WHAT_TO_EXPECT.get(context)
