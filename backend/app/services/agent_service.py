"""Core AI chat agent service.

Orchestrates: redaction → intent classification → tool-calling LLM loop → safety check → response.
The LLM never sees raw PII/PHI — all data is masked before prompt construction.
The LLM proposes tool calls; the backend executes them and feeds results back.
"""

from __future__ import annotations

import json
import logging
import os
import re
import uuid
from typing import Any

import anthropic

from app.schemas.agent import (
    AgentChatResponse,
    AgentContextType,
    SafetyMeta,
    SuggestedAction,
)
from app.services.agent_tools import (
    TOOL_DEFINITIONS,
    ToolAuthContext,
    execute_tool,
)
from app.utils.redaction import Redactor

logger = logging.getLogger(__name__)

MODEL = "claude-haiku-4-5-20251001"
MAX_TOKENS = 1024
MAX_TOOL_ROUNDS = 5  # Prevent infinite tool loops

# ── Crisis patterns (subset of safety_patterns.py adapted for chat input) ────
_CRISIS_PATTERNS = [
    re.compile(
        r"\b(want\s+to\s+(die|end\s+(it|my\s+life|everything))|"
        r"kill\s+myself|suicid(e|al)|"
        r"don\'?t\s+want\s+to\s+(be\s+alive|live|exist)|"
        r"better\s+off\s+dead|end(ing)?\s+my\s+life|"
        r"take\s+my\s+(own\s+)?life)",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(cut(ting)?\s+myself|hurt(ing)?\s+myself|"
        r"burn(ing)?\s+myself|hit(ting)?\s+myself)",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(kill\s+(him|her|them|someone)|"
        r"want\s+to\s+hurt\s+(him|her|them|someone))",
        re.IGNORECASE,
    ),
]

# ── Intent keywords for lightweight client-side classification ────────────────
_SCHEDULING_KEYWORDS = re.compile(
    r"\b(book|schedule|appointment|reschedule|cancel|available|slot|session|next\s+tuesday|"
    r"next\s+week|this\s+week|tomorrow|time)\b",
    re.IGNORECASE,
)
_ONBOARDING_KEYWORDS = re.compile(
    r"\b(new\s+patient|register|sign\s+up|first\s+time|intake|onboard|getting\s+started|new\s+here)\b",
    re.IGNORECASE,
)
_EMOTIONAL_KEYWORDS = re.compile(
    r"\b(overwhelmed|anxious|scared|depressed|stressed|panic|afraid|lonely|sad|hopeless|"
    r"can\'?t\s+cope|feeling\s+(bad|terrible|awful|down))\b",
    re.IGNORECASE,
)
_DOCUMENT_KEYWORDS = re.compile(
    r"\b(upload|insurance\s+card|id\s+card|document|photo|scan|image|form)\b",
    re.IGNORECASE,
)

# ── System prompt templates per context ───────────────────────────────────────
_BASE_RULES = (
    "\n\nRULES:\n"
    "- Be warm, concise, and validating.\n"
    "- NEVER provide diagnoses, medication advice, prescription recommendations, "
    "or clinical recommendations of any kind.\n"
    "- NEVER suggest, recommend, or discuss specific medications, supplements, "
    "dosages, or treatments. If asked about medication, direct the user to "
    "their prescribing provider or therapist.\n"
    "- NEVER provide medical advice, including advice about symptoms, conditions, "
    "side effects, drug interactions, or whether to start/stop/change any treatment.\n"
    "- If the user expresses crisis or self-harm ideation, immediately encourage "
    "them to contact 988 Suicide & Crisis Lifeline or go to the nearest ER.\n"
    "- Do not ask for or repeat personal identifying information.\n"
    "- Keep responses under 3 short paragraphs.\n"
    "- Any identifiers in the conversation have been replaced with tokens like "
    "[NAME_1] or [EMAIL_1]. Do not attempt to guess real values behind tokens.\n"
    "- You have access to tools. Use them when appropriate — e.g., call "
    "get_current_datetime before resolving relative dates like 'next Tuesday', "
    "call get_available_slots before suggesting times, etc.\n"
    "- When booking or cancelling, ALWAYS use the tools rather than just describing the action.\n"
    "- After a tool call succeeds, summarize the result naturally for the user."
)

_DISCLAIMER = (
    "\n\n---\n*This is an AI assistant and does not provide medical advice, "
    "diagnoses, or treatment recommendations. Always consult a qualified "
    "healthcare provider for medical questions.*"
)

_SYSTEM_PROMPTS: dict[AgentContextType, str] = {
    AgentContextType.general: (
        "You are a supportive, empathetic AI assistant for a mental health "
        "care platform. You help users with onboarding, scheduling appointments, and "
        "answering general questions about the platform."
        + _BASE_RULES
    ),
    AgentContextType.onboarding: (
        "You are a supportive AI assistant helping a new user through the "
        "onboarding process. Guide them step by step: welcome them, explain what to "
        "expect, help them understand what information is needed, and make the process "
        "feel approachable."
        + _BASE_RULES
    ),
    AgentContextType.scheduling: (
        "You are a supportive AI assistant helping a user schedule, reschedule, or "
        "cancel a therapy appointment. Help them find suitable times "
        "and walk them through the process.\n"
        "When the user asks to schedule, first call get_current_datetime to know today's date, "
        "then call get_available_slots to find open times. Present the options clearly. "
        "When the user picks a slot, call book_appointment with the correct slot_id."
        + _BASE_RULES
    ),
    AgentContextType.emotional_support: (
        "You are a supportive AI assistant. The user appears to be "
        "experiencing emotional distress. Your role is to:\n"
        "- Validate their feelings without minimizing.\n"
        "- Use the get_validation_message tool to provide warm acknowledgment.\n"
        "- Use get_grounding_exercise if they need a calming technique.\n"
        "- Use get_psychoeducation for educational content about anxiety, therapy, etc.\n"
        "- Encourage them to speak with their therapist or a professional."
        + _BASE_RULES
    ),
    AgentContextType.document_upload: (
        "You are a supportive AI assistant helping a user upload and verify documents "
        "(insurance cards, ID, intake forms). Guide them through the "
        "upload process and confirm extracted information."
        + _BASE_RULES
    ),
}

# ── Suggested actions per context ─────────────────────────────────────────────
_SUGGESTED_ACTIONS: dict[AgentContextType, list[SuggestedAction]] = {
    AgentContextType.general: [
        SuggestedAction(label="Help me get started", payload="I'm new and want to get started"),
        SuggestedAction(label="Schedule an appointment", payload="I'd like to schedule an appointment"),
    ],
    AgentContextType.onboarding: [
        SuggestedAction(label="Start onboarding", payload="I'd like to start the onboarding process"),
        SuggestedAction(label="Upload a document", payload="I want to upload my insurance card"),
        SuggestedAction(label="What do I need?", payload="What information do I need to provide?"),
    ],
    AgentContextType.scheduling: [
        SuggestedAction(label="Find available times", payload="What times are available this week?"),
        SuggestedAction(label="Reschedule my appointment", payload="I need to reschedule my appointment"),
        SuggestedAction(label="Cancel appointment", payload="I need to cancel my appointment"),
    ],
    AgentContextType.emotional_support: [
        SuggestedAction(label="Talk to someone now", payload="I need to talk to someone right now"),
        SuggestedAction(label="Breathing exercise", payload="Can you guide me through a breathing exercise?"),
        SuggestedAction(label="Schedule a session", payload="I'd like to schedule a session with my therapist"),
    ],
    AgentContextType.document_upload: [
        SuggestedAction(label="Upload insurance card", payload="I want to upload my insurance card"),
        SuggestedAction(label="Upload ID", payload="I want to upload my ID"),
        SuggestedAction(label="What documents do I need?", payload="What documents do I need to provide?"),
    ],
}

# Crisis response template
_CRISIS_RESPONSE = (
    "I hear you, and I want you to know that you're not alone. What you're feeling matters.\n\n"
    "Please reach out for immediate support:\n"
    "- **988 Suicide & Crisis Lifeline**: Call or text **988** (available 24/7)\n"
    "- **Crisis Text Line**: Text **HOME** to **741741**\n"
    "- **Emergency**: Call **911** or go to your nearest emergency room\n\n"
    "A trained counselor is ready to help right now. Would you like help finding "
    "additional resources or scheduling an appointment with your therapist?"
)


class AgentService:
    """Orchestrates the chat agent pipeline with privacy-preserving redaction and tool calling."""

    def __init__(self) -> None:
        self.redactor = Redactor()

    def classify_intent(self, message: str) -> AgentContextType:
        """Lightweight keyword-based intent classification."""
        if _DOCUMENT_KEYWORDS.search(message):
            return AgentContextType.document_upload
        if _SCHEDULING_KEYWORDS.search(message):
            return AgentContextType.scheduling
        if _ONBOARDING_KEYWORDS.search(message):
            return AgentContextType.onboarding
        if _EMOTIONAL_KEYWORDS.search(message):
            return AgentContextType.emotional_support
        return AgentContextType.general

    def check_input_safety(self, message: str) -> SafetyMeta:
        """Check user input for crisis language. Returns safety metadata."""
        for pattern in _CRISIS_PATTERNS:
            if pattern.search(message):
                return SafetyMeta(
                    flagged=True,
                    flag_type="crisis",
                    escalated=True,
                )
        return SafetyMeta(flagged=False)

    def check_response_safety(self, response: str) -> SafetyMeta:
        """Check agent response for harmful clinical or medical content."""
        # Diagnosis patterns
        diagnosis_pattern = re.compile(
            r"\b(you\s+(have|suffer\s+from|are\s+diagnosed\s+with)\s+"
            r"(depression|anxiety|bipolar|ptsd|adhd|ocd|bpd|schizophren|"
            r"major\s+depressive|generalized\s+anxiety|panic\s+disorder|"
            r"social\s+anxiety|eating\s+disorder|personality\s+disorder|"
            r"dissociative|psychosis|mania|autis|asperg)|"
            r"your\s+diagnosis\s+is|"
            r"I\s+diagnose)",
            re.IGNORECASE,
        )
        if diagnosis_pattern.search(response):
            return SafetyMeta(flagged=True, flag_type="inappropriate_clinical_advice")

        # Medication / prescription advice patterns
        medication_pattern = re.compile(
            r"\b(you\s+should\s+take\s+\w+[\s\w.]*(mg|milligram)|"
            r"(tak(e|ing)|try(ing)?|start(ing)?|increas(e|ing)|decreas(e|ing)|stop\s+taking|switch(ing)?\s+to)\s+"
            r"(sertraline|prozac|fluoxetine|zoloft|lexapro|escitalopram|"
            r"citalopram|celexa|paxil|paroxetine|wellbutrin|bupropion|"
            r"effexor|venlafaxine|cymbalta|duloxetine|xanax|alprazolam|"
            r"klonopin|clonazepam|ativan|lorazepam|valium|diazepam|"
            r"ambien|zolpidem|trazodone|buspirone|lithium|lamictal|"
            r"lamotrigine|abilify|aripiprazole|seroquel|quetiapine|"
            r"risperdal|risperidone|adderall|ritalin|concerta|vyvanse|"
            r"gabapentin|pregabalin|hydroxyzine|propranolol|clonidine)|"
            r"I\s+(recommend|prescribe|suggest)\s+\w+[\s\w.]*(mg|milligram|daily|twice|weekly)|"
            r"(dosage|dose)\s+(of|should\s+be|is)\s+\d+\s*(mg|milligram)|"
            r"\d+\s*(mg|milligram)\s+(daily|twice|once|every|per\s+day))",
            re.IGNORECASE,
        )
        if medication_pattern.search(response):
            return SafetyMeta(flagged=True, flag_type="inappropriate_medical_advice")

        # General medical advice patterns
        medical_advice_pattern = re.compile(
            r"\b(you\s+should\s+(stop|start|change|adjust|increase|decrease)\s+"
            r"(your\s+)?(medication|treatment|dosage|prescription|therapy\s+medication)|"
            r"(stop|don'?t)\s+taking\s+your\s+(medication|prescription|pills))",
            re.IGNORECASE,
        )
        if medical_advice_pattern.search(response):
            return SafetyMeta(flagged=True, flag_type="inappropriate_medical_advice")

        return SafetyMeta(flagged=False)

    def build_llm_messages(
        self,
        user_message: str,
        history: list[dict[str, str]],
        context_type: AgentContextType,
    ) -> tuple[str, list[dict[str, Any]]]:
        """Build the message list for the LLM with redacted content.

        Returns (system_prompt, messages) ready for the Anthropic API.
        """
        system_prompt = _SYSTEM_PROMPTS.get(
            context_type, _SYSTEM_PROMPTS[AgentContextType.general]
        )

        messages: list[dict[str, Any]] = []

        # Add conversation history (already redacted when stored)
        for msg in history:
            messages.append({"role": msg["role"], "content": msg["content"]})

        # Redact the new user message
        redacted = self.redactor.redact(user_message)
        messages.append({"role": "user", "content": redacted.redacted_text})

        return system_prompt, messages

    def get_suggested_actions(self, context_type: AgentContextType) -> list[SuggestedAction]:
        """Return context-appropriate suggested actions."""
        return _SUGGESTED_ACTIONS.get(context_type, _SUGGESTED_ACTIONS[AgentContextType.general])

    async def _call_llm_with_tools(
        self,
        system_prompt: str,
        messages: list[dict[str, Any]],
        auth: ToolAuthContext,
        db: Any | None = None,
    ) -> str:
        """Multi-turn tool-calling loop.

        1. Send messages + tool definitions to the LLM.
        2. If the LLM returns tool_use blocks, execute each tool server-side.
        3. Append tool results and call the LLM again.
        4. Repeat until the LLM returns a text response (no more tool calls) or we hit MAX_TOOL_ROUNDS.
        """
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY is not set")

        client = anthropic.AsyncAnthropic(api_key=api_key)

        for round_num in range(MAX_TOOL_ROUNDS):
            response = await client.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                system=system_prompt,
                messages=messages,
                tools=TOOL_DEFINITIONS,
            )

            # Collect text and tool_use blocks
            text_parts: list[str] = []
            tool_uses: list[dict[str, Any]] = []

            for block in response.content:
                if block.type == "text":
                    text_parts.append(block.text)
                elif block.type == "tool_use":
                    tool_uses.append({
                        "id": block.id,
                        "name": block.name,
                        "input": block.input,
                    })

            # If no tool calls, we're done — return the text
            if not tool_uses:
                return "\n".join(text_parts) if text_parts else ""

            # If the LLM used tools, append the assistant message, execute tools,
            # and append tool results.
            # The assistant message must include the full content blocks.
            assistant_content = []
            for block in response.content:
                if block.type == "text":
                    assistant_content.append({"type": "text", "text": block.text})
                elif block.type == "tool_use":
                    assistant_content.append({
                        "type": "tool_use",
                        "id": block.id,
                        "name": block.name,
                        "input": block.input,
                    })

            messages.append({"role": "assistant", "content": assistant_content})

            # Execute each tool and collect results
            tool_results = []
            for tool_call in tool_uses:
                logger.info(
                    "Executing tool: %s (round %d)",
                    tool_call["name"],
                    round_num + 1,
                )
                result = await execute_tool(
                    tool_name=tool_call["name"],
                    tool_input=tool_call["input"],
                    auth=auth,
                    db=db,
                )
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_call["id"],
                    "content": json.dumps(result),
                })

            messages.append({"role": "user", "content": tool_results})

        # If we exhausted all rounds, return whatever text we have
        return "\n".join(text_parts) if text_parts else (
            "I'm sorry, I wasn't able to complete that action. Please try again."
        )

    async def process_message(
        self,
        user_message: str,
        conversation_id: str | None,
        context_type: AgentContextType,
        user_id: int,
        history: list[dict[str, str]] | None = None,
        auth: ToolAuthContext | None = None,
        db: Any | None = None,
    ) -> AgentChatResponse:
        """Full pipeline: classify → safety check → redact → tool-calling LLM loop → safety check → respond."""

        # Generate conversation ID if new
        if not conversation_id:
            conversation_id = str(uuid.uuid4())

        # Check input safety first
        input_safety = self.check_input_safety(user_message)
        if input_safety.escalated:
            return AgentChatResponse(
                message=_CRISIS_RESPONSE + _DISCLAIMER,
                conversation_id=conversation_id,
                suggested_actions=[
                    SuggestedAction(label="Schedule urgent session", payload="I need to see my therapist soon"),
                    SuggestedAction(label="More resources", payload="Can you share more crisis resources?"),
                ],
                safety=input_safety,
                context_type=AgentContextType.emotional_support,
            )

        # Classify intent (may override provided context_type)
        classified = self.classify_intent(user_message)
        effective_context = classified if classified != AgentContextType.general else context_type

        # Redirect: client without profile trying to schedule → onboarding first
        redirected_from_scheduling = False
        if (
            effective_context == AgentContextType.scheduling
            and auth.role == "client"
            and auth.client_id is None
        ):
            effective_context = AgentContextType.onboarding
            redirected_from_scheduling = True

        # Build redacted prompt
        system_prompt, llm_messages = self.build_llm_messages(
            user_message=user_message,
            history=history or [],
            context_type=effective_context,
        )

        if redirected_from_scheduling:
            system_prompt += (
                "\n\nIMPORTANT: The user asked to schedule an appointment but has not completed "
                "onboarding (no client profile). Guide them through onboarding first. Explain "
                "what information is needed and that once their profile is set up, they can "
                "schedule. Do not call scheduling tools until they have completed onboarding."
            )
        elif (
            effective_context == AgentContextType.scheduling
            and auth.role == "client"
            and auth.therapist_id is not None
        ):
            system_prompt += (
                f"\n\nIMPORTANT: The user is a client with an assigned therapist. "
                f"Use therapist_id {auth.therapist_id} for get_available_slots and book_appointment. "
                "Do NOT ask which therapist they want to see — proceed directly to showing available times."
            )

        # Build auth context if not provided
        if auth is None:
            auth = ToolAuthContext(user_id=user_id, role="client")

        # Call LLM with tool-calling loop
        try:
            response_text = await self._call_llm_with_tools(
                system_prompt=system_prompt,
                messages=llm_messages,
                auth=auth,
                db=db,
            )
        except Exception as e:
            logger.error("LLM call failed: %s", e)
            response_text = (
                "I'm sorry, I'm having trouble processing your request right now. "
                "Please try again in a moment, or contact support if this continues."
            )

        # Post-process: safety check on response
        response_safety = self.check_response_safety(response_text)
        if response_safety.flagged:
            logger.warning("Agent response flagged for safety: %s", response_safety.flag_type)
            response_text = (
                "I want to make sure I'm being helpful in the right way. "
                "I'm not able to provide medical advice, diagnoses, or medication recommendations. "
                "Please speak directly with your therapist or prescribing provider "
                "for clinical questions. Is there something else I can help you with?"
            )

        # Append disclaimer to all responses
        response_text += _DISCLAIMER

        # Get suggested actions
        suggested = self.get_suggested_actions(effective_context)
        if redirected_from_scheduling:
            suggested = [
                *suggested,
                SuggestedAction(
                    label="I'm ready to schedule",
                    payload="I've completed onboarding, I'd like to schedule an appointment",
                ),
            ]

        return AgentChatResponse(
            message=response_text,
            conversation_id=conversation_id,
            suggested_actions=suggested,
            follow_up_questions=[],
            safety=SafetyMeta(flagged=False),
            context_type=effective_context,
        )
