"""Eval tests for the chat agent.

These tests verify end-to-end agent behavior across the 10 example conversation
flows. The Anthropic API is mocked to return deterministic responses, but
everything else runs for real: redaction, safety checks, intent classification,
tool execution, auth validation.

Each test asserts on observable outcomes:
- PII is never in the agent's final response
- Crisis messages short-circuit the LLM
- Tools are executed with correct parameters
- Auth boundaries are enforced
- Response safety catches clinical advice
"""

import json
import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

from app.schemas.agent import AgentContextType
from app.services.agent_service import AgentService, _DISCLAIMER
from app.services.agent_tools import ToolAuthContext, execute_tool


# ── Helpers ──────────────────────────────────────────────────────────────────

def _make_text_response(text: str):
    """Simulate an Anthropic API response with just text (no tool calls)."""
    block = MagicMock()
    block.type = "text"
    block.text = text
    response = MagicMock()
    response.content = [block]
    return response


def _make_tool_use_response(tool_calls: list[dict], text: str = ""):
    """Simulate an Anthropic API response with tool_use blocks.

    tool_calls: [{"id": "tu_1", "name": "get_current_datetime", "input": {}}]
    """
    blocks = []
    if text:
        text_block = MagicMock()
        text_block.type = "text"
        text_block.text = text
        blocks.append(text_block)

    for tc in tool_calls:
        tool_block = MagicMock()
        tool_block.type = "tool_use"
        tool_block.id = tc["id"]
        tool_block.name = tc["name"]
        tool_block.input = tc.get("input", {})
        blocks.append(tool_block)

    response = MagicMock()
    response.content = blocks
    return response


def _client_auth(client_id: int = 10) -> ToolAuthContext:
    return ToolAuthContext(user_id=2, role="client", client_id=client_id)


def _therapist_auth(therapist_id: int = 1) -> ToolAuthContext:
    return ToolAuthContext(user_id=1, role="therapist", therapist_id=therapist_id)


# ── Flow 1: Onboarding with PII redaction ───────────────────────────────────

class TestFlow1OnboardingPII:
    """User provides PII during onboarding — agent must not repeat it."""

    @pytest.mark.asyncio
    async def test_pii_redacted_before_llm(self):
        """Verify redaction happens before the LLM sees the message."""
        service = AgentService()
        system_prompt, messages = service.build_llm_messages(
            user_message="My name is Sarah Johnson and my email is sarah.j@gmail.com",
            history=[],
            context_type=AgentContextType.onboarding,
        )
        user_msg = messages[-1]["content"]
        assert "Sarah Johnson" not in user_msg
        assert "sarah.j@gmail.com" not in user_msg
        assert "[NAME_1]" in user_msg
        assert "[EMAIL_1]" in user_msg

    @pytest.mark.asyncio
    async def test_agent_response_contains_no_pii(self):
        """End-to-end: agent response must not contain raw PII."""
        service = AgentService()

        with patch("app.services.agent_service.anthropic") as mock_anthropic, \
             patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            mock_client = AsyncMock()
            mock_anthropic.AsyncAnthropic.return_value = mock_client
            mock_client.messages.create = AsyncMock(return_value=_make_text_response(
                "Thanks [NAME_1]! I've noted your email. Let's get you started with onboarding."
            ))

            result = await service.process_message(
                user_message="My name is Sarah Johnson and my email is sarah.j@gmail.com",
                conversation_id=None,
                context_type=AgentContextType.onboarding,
                user_id=1,
                auth=_client_auth(),
            )

            assert "Sarah Johnson" not in result.message
            assert "sarah.j@gmail.com" not in result.message
            # Disclaimer must be present on every response
            assert "does not provide medical advice" in result.message

    @pytest.mark.asyncio
    async def test_policy_number_redacted(self):
        """Policy numbers should be replaced with tokens."""
        service = AgentService()
        system_prompt, messages = service.build_llm_messages(
            user_message="My insurance policy number: ABC-12345-XYZ",
            history=[],
            context_type=AgentContextType.onboarding,
        )
        user_msg = messages[-1]["content"]
        assert "ABC-12345-XYZ" not in user_msg
        assert "[POLICY_1]" in user_msg


# ── Flow 2: Client scheduling (tool calling) ────────────────────────────────

class TestFlow2ClientScheduling:
    """Client asks to schedule — agent should use datetime + scheduling tools."""

    @pytest.mark.asyncio
    async def test_intent_classified_as_scheduling(self):
        service = AgentService()
        intent = service.classify_intent("I'd like to schedule an appointment with my therapist")
        assert intent == AgentContextType.scheduling

    @pytest.mark.asyncio
    async def test_scheduling_uses_tools(self):
        """When the LLM calls get_available_slots, verify tool execution."""
        service = AgentService()

        call_count = 0

        async def mock_create(**kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                # First call: LLM requests datetime and availability
                return _make_tool_use_response([
                    {"id": "tu_1", "name": "get_current_datetime", "input": {}},
                ])
            elif call_count == 2:
                # Second call: LLM requests availability
                return _make_tool_use_response([
                    {"id": "tu_2", "name": "get_available_slots", "input": {"therapist_id": 1}},
                ])
            else:
                # Final call: LLM presents slots to user
                return _make_text_response(
                    "Here are the available times this week:\n"
                    "• Monday at 9:00 AM\n"
                    "• Monday at 1:00 PM\n"
                    "Which works best for you?"
                )

        with patch("app.services.agent_service.anthropic") as mock_anthropic, \
             patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            mock_client = AsyncMock()
            mock_anthropic.AsyncAnthropic.return_value = mock_client
            mock_client.messages.create = mock_create

            # Mock DB for scheduling service
            mock_db = AsyncMock()
            mock_therapist = MagicMock()
            mock_therapist.id = 1
            mock_result = MagicMock()
            mock_result.scalar_one_or_none.return_value = mock_therapist
            mock_db.execute = AsyncMock(return_value=mock_result)

            result = await service.process_message(
                user_message="I'd like to schedule an appointment",
                conversation_id=None,
                context_type=AgentContextType.general,
                user_id=2,
                auth=_client_auth(),
                db=mock_db,
            )

            assert result.context_type == AgentContextType.scheduling
            assert "available" in result.message.lower() or "time" in result.message.lower()
            assert "does not provide medical advice" in result.message


# ── Flow 3: Therapist delegation booking ─────────────────────────────────────

class TestFlow3TherapistDelegation:
    """Therapist books on behalf of their client via tool calling."""

    @pytest.mark.asyncio
    async def test_therapist_book_tool_passes_correct_auth(self):
        """When therapist books, acting_therapist_id must be passed."""
        auth = _therapist_auth(therapist_id=1)

        # Mock DB interactions
        mock_db = AsyncMock()

        # Client exists and belongs to this therapist
        client_mock = MagicMock()
        client_mock.id = 10
        client_mock.therapist_id = 1

        therapist_mock = MagicMock()
        therapist_mock.id = 1

        call_count = 0

        async def mock_execute(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            result = MagicMock()
            if call_count <= 2:
                # Client lookup + relationship check
                result.scalar_one_or_none.return_value = client_mock
            elif call_count == 3:
                # Therapist lookup
                result.scalar_one_or_none.return_value = therapist_mock
            else:
                # Session count
                result.scalars.return_value.all.return_value = []
            return result

        mock_db.execute = AsyncMock(side_effect=mock_execute)
        mock_db.commit = AsyncMock()
        mock_db.refresh = AsyncMock()

        result = await execute_tool(
            tool_name="book_appointment",
            tool_input={"therapist_id": 1, "slot_id": "slot-1-3", "client_id": 10},
            auth=auth,
            db=mock_db,
        )

        assert result.get("status") == "confirmed"
        assert result.get("slot_id") == "slot-1-3"


# ── Flow 4: Therapist blocked (wrong client) ────────────────────────────────

class TestFlow4TherapistBlocked:
    """Therapist tries to book for a client not in their caseload."""

    @pytest.mark.asyncio
    async def test_cross_therapist_booking_rejected(self):
        """Therapist 2 cannot book for Therapist 1's client."""
        auth = _therapist_auth(therapist_id=2)

        mock_db = AsyncMock()

        client_mock = MagicMock()
        client_mock.id = 10
        client_mock.therapist_id = 1  # Belongs to therapist 1, not 2

        call_count = 0

        async def mock_execute(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            result = MagicMock()
            if call_count == 1:
                result.scalar_one_or_none.return_value = client_mock
            else:
                # Relationship check — no match
                result.scalar_one_or_none.return_value = None
            return result

        mock_db.execute = AsyncMock(side_effect=mock_execute)

        result = await execute_tool(
            tool_name="book_appointment",
            tool_input={"therapist_id": 1, "slot_id": "slot-1-3", "client_id": 10},
            auth=auth,
            db=mock_db,
        )

        assert "error" in result
        assert "not authorized" in result["error"]

    @pytest.mark.asyncio
    async def test_therapist_missing_client_id(self):
        """Therapist must specify client_id for delegation."""
        auth = _therapist_auth(therapist_id=1)

        result = await execute_tool(
            tool_name="book_appointment",
            tool_input={"therapist_id": 1, "slot_id": "slot-1-3"},
            auth=auth,
            db=AsyncMock(),
        )

        assert "error" in result
        assert "client_id" in result["error"]


# ── Flow 5: Crisis detection (short-circuit) ────────────────────────────────

class TestFlow5Crisis:
    """Crisis messages must short-circuit the LLM call entirely."""

    @pytest.mark.asyncio
    async def test_crisis_response_no_llm_call(self):
        """When crisis detected, response is hardcoded — no LLM call made."""
        service = AgentService()

        with patch("app.services.agent_service.anthropic") as mock_anthropic:
            mock_client = AsyncMock()
            mock_anthropic.AsyncAnthropic.return_value = mock_client

            result = await service.process_message(
                user_message="I don't want to be alive anymore",
                conversation_id=None,
                context_type=AgentContextType.general,
                user_id=1,
                auth=_client_auth(),
            )

            # LLM should NOT have been called
            mock_client.messages.create.assert_not_called()

            # Response should contain crisis resources
            assert "988" in result.message
            assert "741741" in result.message or "Crisis Text Line" in result.message
            assert "911" in result.message
            assert "does not provide medical advice" in result.message

            # Safety metadata
            assert result.safety.flagged is True
            assert result.safety.flag_type == "crisis"
            assert result.safety.escalated is True
            assert result.context_type == AgentContextType.emotional_support

    @pytest.mark.asyncio
    async def test_self_harm_detected(self):
        service = AgentService()
        safety = service.check_input_safety("I've been cutting myself")
        assert safety.flagged is True
        assert safety.escalated is True

    @pytest.mark.asyncio
    async def test_harm_to_others_detected(self):
        service = AgentService()
        safety = service.check_input_safety("I want to hurt someone")
        assert safety.flagged is True


# ── Flow 6: Emotional support (tool calling) ────────────────────────────────

class TestFlow6EmotionalSupport:
    """Anxious user gets validation + grounding exercise via tools."""

    @pytest.mark.asyncio
    async def test_emotional_intent_detected(self):
        service = AgentService()
        intent = service.classify_intent("I'm feeling really anxious and overwhelmed right now")
        assert intent == AgentContextType.emotional_support

    @pytest.mark.asyncio
    async def test_grounding_tool_returns_exercise(self):
        """get_grounding_exercise tool returns a real exercise."""
        result = await execute_tool(
            tool_name="get_grounding_exercise",
            tool_input={},
            auth=_client_auth(),
        )
        assert "exercise" in result
        exercise = result["exercise"]
        assert any(word in exercise.lower() for word in ["breathe", "see", "touch", "hear", "feet", "ground"])

    @pytest.mark.asyncio
    async def test_validation_tool_returns_message(self):
        result = await execute_tool(
            tool_name="get_validation_message",
            tool_input={},
            auth=_client_auth(),
        )
        assert "message" in result
        assert len(result["message"]) > 0

    @pytest.mark.asyncio
    async def test_psychoeducation_tool(self):
        result = await execute_tool(
            tool_name="get_psychoeducation",
            tool_input={"topic": "anxiety"},
            auth=_client_auth(),
        )
        assert "content" in result
        assert "anxiety" in result["content"].lower() or "natural" in result["content"].lower()

    @pytest.mark.asyncio
    async def test_what_to_expect_tool(self):
        result = await execute_tool(
            tool_name="get_what_to_expect",
            tool_input={"context": "first_appointment"},
            auth=_client_auth(),
        )
        assert "content" in result
        assert "50 minutes" in result["content"] or "appointment" in result["content"].lower()


# ── Flow 7: PII boundary testing ────────────────────────────────────────────

class TestFlow7PIIBoundary:
    """All 6 PII types in one message must be fully redacted."""

    @pytest.mark.asyncio
    async def test_all_pii_types_redacted(self):
        service = AgentService()
        message = (
            "My name is John Smith, DOB: 03/15/1990, SSN 123-45-6789, "
            "I live at 456 Oak Avenue, and my phone is (555) 867-5309."
        )
        system_prompt, messages = service.build_llm_messages(
            user_message=message,
            history=[],
            context_type=AgentContextType.general,
        )
        user_msg = messages[-1]["content"]

        # All PII should be gone
        assert "John Smith" not in user_msg
        assert "03/15/1990" not in user_msg
        assert "123-45-6789" not in user_msg
        assert "456 Oak Avenue" not in user_msg
        assert "(555) 867-5309" not in user_msg

        # Tokens should be present
        assert "[NAME_1]" in user_msg
        assert "[DOB_1]" in user_msg
        assert "[SSN_1]" in user_msg
        assert "[ADDRESS_1]" in user_msg
        assert "[PHONE_1]" in user_msg

    @pytest.mark.asyncio
    async def test_email_redacted(self):
        service = AgentService()
        system_prompt, messages = service.build_llm_messages(
            user_message="My email is john.doe@company.org",
            history=[],
            context_type=AgentContextType.general,
        )
        user_msg = messages[-1]["content"]
        assert "john.doe@company.org" not in user_msg
        assert "[EMAIL_1]" in user_msg


# ── Flow 8: Response safety — clinical advice blocked ────────────────────────

class TestFlow8ResponseSafety:
    """LLM responses with clinical advice must be caught and replaced."""

    @pytest.mark.asyncio
    async def test_diagnosis_blocked(self):
        service = AgentService()

        with patch("app.services.agent_service.anthropic") as mock_anthropic, \
             patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            mock_client = AsyncMock()
            mock_anthropic.AsyncAnthropic.return_value = mock_client
            mock_client.messages.create = AsyncMock(return_value=_make_text_response(
                "Based on what you're describing, you have major depressive disorder. "
                "You should take sertraline 50mg daily."
            ))

            result = await service.process_message(
                user_message="I've been feeling sad for weeks and can't sleep",
                conversation_id=None,
                context_type=AgentContextType.emotional_support,
                user_id=1,
                auth=_client_auth(),
            )

            # The diagnosis should have been caught and replaced with safe deflection
            assert "major depressive" not in result.message
            assert "sertraline" not in result.message
            assert "therapist" in result.message.lower() or "provider" in result.message.lower()
            assert "does not provide medical advice" in result.message

    @pytest.mark.asyncio
    async def test_medication_advice_blocked(self):
        service = AgentService()
        safety = service.check_response_safety(
            "you should take sertraline 50mg for your depression"
        )
        assert safety.flagged is True
        assert "inappropriate" in safety.flag_type

    @pytest.mark.asyncio
    async def test_scheduling_response_not_blocked(self):
        """Scheduling responses like 'you have an appointment' must NOT be flagged."""
        service = AgentService()
        for text in [
            "You have the following available times this week.",
            "You have an appointment scheduled for Tuesday at 1pm.",
            "You have several options to choose from.",
            "Here are the available times — you have 3 open slots.",
        ]:
            safety = service.check_response_safety(text)
            assert safety.flagged is False, f"Falsely flagged: {text!r}"

    @pytest.mark.asyncio
    async def test_prescription_advice_blocked(self):
        """Specific medication recommendations must be caught."""
        service = AgentService()
        cases = [
            "You could try sertraline for your anxiety",
            "I'd suggest starting lexapro at a low dose",
            "Try taking xanax when you feel anxious",
            "The dosage should be 50 mg daily",
            "Take 20mg twice daily for best results",
        ]
        for text in cases:
            safety = service.check_response_safety(text)
            assert safety.flagged is True, f"Should have flagged: {text!r}"
            assert "medical" in safety.flag_type or "clinical" in safety.flag_type

    @pytest.mark.asyncio
    async def test_medical_treatment_advice_blocked(self):
        """Advice to change medication/treatment must be caught."""
        service = AgentService()
        cases = [
            "You should stop your medication and try something else",
            "You should increase your dosage",
            "You should change your prescription",
        ]
        for text in cases:
            safety = service.check_response_safety(text)
            assert safety.flagged is True, f"Should have flagged: {text!r}"

    @pytest.mark.asyncio
    async def test_disclaimer_on_every_response(self):
        """Every agent response must include the medical advice disclaimer."""
        service = AgentService()

        with patch("app.services.agent_service.anthropic") as mock_anthropic, \
             patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            mock_client = AsyncMock()
            mock_anthropic.AsyncAnthropic.return_value = mock_client
            mock_client.messages.create = AsyncMock(return_value=_make_text_response(
                "I'd be happy to help you schedule an appointment!"
            ))

            result = await service.process_message(
                user_message="I want to book an appointment",
                conversation_id=None,
                context_type=AgentContextType.scheduling,
                user_id=1,
                auth=_client_auth(),
            )

            assert _DISCLAIMER in result.message
            assert "does not provide medical advice" in result.message

    @pytest.mark.asyncio
    async def test_safe_response_passes(self):
        service = AgentService()
        safety = service.check_response_safety(
            "It sounds like you're going through a difficult time. "
            "Speaking with your therapist about these feelings could be really helpful."
        )
        assert safety.flagged is False


# ── Flow 9: Document upload intent ──────────────────────────────────────────

class TestFlow9DocumentUpload:
    """Document upload intent is correctly classified."""

    def test_insurance_card_intent(self):
        service = AgentService()
        intent = service.classify_intent("I want to upload my insurance card")
        assert intent == AgentContextType.document_upload

    def test_id_upload_intent(self):
        service = AgentService()
        intent = service.classify_intent("I need to upload a photo of my ID")
        assert intent == AgentContextType.document_upload


# ── Flow 10: Cancellation (client and therapist) ────────────────────────────

class TestFlow10Cancellation:
    """Both client self-service and therapist delegation cancel flows."""

    @pytest.mark.asyncio
    async def test_client_cancel_tool(self):
        """Client cancels their own session via tool."""
        auth = _client_auth(client_id=10)

        session_mock = MagicMock()
        session_mock.id = 100
        session_mock.client_id = 10
        session_mock.therapist_id = 1
        session_mock.status = "scheduled"

        mock_db = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalar_one_or_none.return_value = session_mock
        mock_db.execute = AsyncMock(return_value=result_mock)
        mock_db.commit = AsyncMock()

        result = await execute_tool(
            tool_name="cancel_appointment",
            tool_input={"session_id": 100},
            auth=auth,
            db=mock_db,
        )

        assert result.get("status") == "cancelled"
        assert result.get("session_id") == 100

    @pytest.mark.asyncio
    async def test_therapist_cancel_tool(self):
        """Therapist cancels on behalf of their client."""
        auth = _therapist_auth(therapist_id=1)

        session_mock = MagicMock()
        session_mock.id = 100
        session_mock.client_id = 10
        session_mock.therapist_id = 1
        session_mock.status = "scheduled"

        mock_db = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalar_one_or_none.return_value = session_mock
        mock_db.execute = AsyncMock(return_value=result_mock)
        mock_db.commit = AsyncMock()

        result = await execute_tool(
            tool_name="cancel_appointment",
            tool_input={"session_id": 100, "client_id": 10},
            auth=auth,
            db=mock_db,
        )

        assert result.get("status") == "cancelled"

    @pytest.mark.asyncio
    async def test_therapist_cancel_wrong_session_rejected(self):
        """Therapist cannot cancel another therapist's session."""
        auth = _therapist_auth(therapist_id=2)

        session_mock = MagicMock()
        session_mock.id = 100
        session_mock.client_id = 10
        session_mock.therapist_id = 1  # Belongs to therapist 1
        session_mock.status = "scheduled"

        mock_db = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalar_one_or_none.return_value = session_mock
        mock_db.execute = AsyncMock(return_value=result_mock)

        result = await execute_tool(
            tool_name="cancel_appointment",
            tool_input={"session_id": 100, "client_id": 10},
            auth=auth,
            db=mock_db,
        )

        assert "error" in result
        assert "not authorized" in result["error"]

    @pytest.mark.asyncio
    async def test_cancel_completed_session_rejected(self):
        """Cannot cancel a completed session."""
        auth = _client_auth(client_id=10)

        session_mock = MagicMock()
        session_mock.id = 100
        session_mock.client_id = 10
        session_mock.therapist_id = 1
        session_mock.status = "completed"

        mock_db = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalar_one_or_none.return_value = session_mock
        mock_db.execute = AsyncMock(return_value=result_mock)

        result = await execute_tool(
            tool_name="cancel_appointment",
            tool_input={"session_id": 100},
            auth=auth,
            db=mock_db,
        )

        assert "error" in result
        assert "completed" in result["error"].lower() or "Cannot cancel" in result["error"]


# ── Datetime tool ────────────────────────────────────────────────────────────

class TestDatetimeTool:
    """The datetime tool provides current time info for the LLM."""

    @pytest.mark.asyncio
    async def test_returns_current_date(self):
        result = await execute_tool(
            tool_name="get_current_datetime",
            tool_input={},
            auth=_client_auth(),
        )
        assert "utc" in result
        assert "date" in result
        assert "day_of_week" in result
        assert "mountain_time" in result

    @pytest.mark.asyncio
    async def test_date_is_valid_iso(self):
        result = await execute_tool(
            tool_name="get_current_datetime",
            tool_input={},
            auth=_client_auth(),
        )
        # Should be a valid ISO date
        datetime.fromisoformat(result["utc"])


# ── Tool error handling ──────────────────────────────────────────────────────

class TestToolErrorHandling:
    """Tools must gracefully handle errors."""

    @pytest.mark.asyncio
    async def test_unknown_tool_returns_error(self):
        result = await execute_tool(
            tool_name="nonexistent_tool",
            tool_input={},
            auth=_client_auth(),
        )
        assert "error" in result
        assert "Unknown tool" in result["error"]

    @pytest.mark.asyncio
    async def test_scheduling_without_db_returns_error(self):
        result = await execute_tool(
            tool_name="get_available_slots",
            tool_input={"therapist_id": 1},
            auth=_client_auth(),
            db=None,
        )
        assert "error" in result
        assert "Database" in result["error"]

    @pytest.mark.asyncio
    async def test_unknown_psychoeducation_topic(self):
        result = await execute_tool(
            tool_name="get_psychoeducation",
            tool_input={"topic": "nonexistent"},
            auth=_client_auth(),
        )
        assert "error" in result

    @pytest.mark.asyncio
    async def test_unknown_what_to_expect_context(self):
        result = await execute_tool(
            tool_name="get_what_to_expect",
            tool_input={"context": "nonexistent"},
            auth=_client_auth(),
        )
        assert "error" in result

    @pytest.mark.asyncio
    async def test_client_cancel_without_profile(self):
        """Client with no client_id should get an error."""
        auth = ToolAuthContext(user_id=1, role="client", client_id=None)
        result = await execute_tool(
            tool_name="cancel_appointment",
            tool_input={"session_id": 100},
            auth=auth,
            db=AsyncMock(),
        )
        assert "error" in result
        assert "client profile" in result["error"].lower() or "No client" in result["error"]
