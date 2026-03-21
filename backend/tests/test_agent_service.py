"""Tests for the AI chat agent service.

Validates intent classification, redaction before LLM calls,
safety post-processing, and conversation flow.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.agent_service import AgentService
from app.schemas.agent import AgentContextType
from app.services.agent_tools import ToolAuthContext
from app.utils.redaction import Redactor


class TestAgentServiceRedaction:
    """The agent service must redact PII before sending to LLM."""

    @pytest.fixture
    def service(self):
        return AgentService()

    def test_service_has_redactor(self, service):
        assert isinstance(service.redactor, Redactor)

    @pytest.mark.asyncio
    async def test_build_prompt_redacts_user_message(self, service):
        """User messages containing PII should be redacted in the prompt sent to the LLM."""
        user_msg = "My name is John Smith and my email is john@test.com"
        system_prompt, messages = service.build_llm_messages(
            user_message=user_msg,
            history=[],
            context_type=AgentContextType.general,
        )
        # The user message in the prompt should not contain raw PII
        user_content = [m["content"] for m in messages if m["role"] == "user"]
        assert len(user_content) > 0
        assert "John Smith" not in user_content[-1]
        assert "john@test.com" not in user_content[-1]

    @pytest.mark.asyncio
    async def test_build_prompt_includes_system_message(self, service):
        system_prompt, messages = service.build_llm_messages(
            user_message="Hello",
            history=[],
            context_type=AgentContextType.onboarding,
        )
        assert "onboarding" in system_prompt.lower()

    @pytest.mark.asyncio
    async def test_build_prompt_includes_history(self, service):
        history = [
            {"role": "user", "content": "Hi"},
            {"role": "assistant", "content": "Hello! How can I help?"},
        ]
        system_prompt, messages = service.build_llm_messages(
            user_message="I need to book an appointment",
            history=history,
            context_type=AgentContextType.general,
        )
        # Should have history + new user message (system is separate now)
        assert len(messages) >= 3


class TestAgentServiceSafety:
    """Agent responses must go through safety checks."""

    @pytest.fixture
    def service(self):
        return AgentService()

    def test_check_response_safety_clean(self, service):
        result = service.check_response_safety("Here are some breathing exercises you can try.")
        assert result.flagged is False

    def test_check_response_safety_crisis(self, service):
        result = service.check_response_safety(
            "If you're thinking about ending your life, please call 988."
        )
        # This is a safe response (providing resources), should not be flagged
        assert result.flagged is False

    def test_check_input_safety_crisis_language(self, service):
        """User input with crisis language should be detected."""
        result = service.check_input_safety("I want to kill myself")
        assert result.flagged is True
        assert result.escalated is True

    def test_check_input_safety_normal(self, service):
        result = service.check_input_safety("I'd like to book an appointment for next week")
        assert result.flagged is False


class TestAgentServiceIntentClassification:
    """The service should classify user intent for routing."""

    @pytest.fixture
    def service(self):
        return AgentService()

    def test_classify_scheduling_intent(self, service):
        intent = service.classify_intent("I need to book an appointment for next Tuesday")
        assert intent == AgentContextType.scheduling

    def test_classify_onboarding_intent(self, service):
        intent = service.classify_intent("I'm a new patient and need to register")
        assert intent == AgentContextType.onboarding

    def test_classify_emotional_support_intent(self, service):
        intent = service.classify_intent("I'm feeling really overwhelmed and anxious right now")
        assert intent == AgentContextType.emotional_support

    def test_classify_document_intent(self, service):
        intent = service.classify_intent("I want to upload my insurance card")
        assert intent == AgentContextType.document_upload

    def test_classify_general_intent(self, service):
        intent = service.classify_intent("What services do you offer?")
        assert intent == AgentContextType.general


class TestSuggestedActions:
    """The service should generate context-appropriate suggested actions."""

    @pytest.fixture
    def service(self):
        return AgentService()

    def test_onboarding_suggestions(self, service):
        actions = service.get_suggested_actions(AgentContextType.onboarding)
        assert len(actions) > 0
        labels = [a.label for a in actions]
        assert any("upload" in l.lower() or "document" in l.lower() or "start" in l.lower() for l in labels)

    def test_scheduling_suggestions(self, service):
        actions = service.get_suggested_actions(AgentContextType.scheduling)
        assert len(actions) > 0
        labels = [a.label for a in actions]
        assert any("appointment" in l.lower() or "schedule" in l.lower() or "available" in l.lower() for l in labels)


class TestOnboardingRedirect:
    """Non-onboarded clients requesting scheduling should be redirected to onboarding first."""

    @pytest.fixture
    def service(self):
        return AgentService()

    @pytest.mark.asyncio
    @patch("app.services.agent_service.AgentService._call_llm_with_tools", new_callable=AsyncMock)
    async def test_client_without_profile_scheduling_redirects_to_onboarding(
        self, mock_llm, service
    ):
        """Client with no client_profile asking to schedule gets onboarding flow + schedule CTA."""
        mock_llm.return_value = "Let me help you get set up first. What's your name?"
        auth = ToolAuthContext(user_id=1, role="client", client_id=None, therapist_id=None)

        response = await service.process_message(
            user_message="I'd like to book an appointment",
            conversation_id=None,
            context_type=AgentContextType.general,
            user_id=1,
            history=[],
            auth=auth,
            db=None,
        )

        assert response.context_type == AgentContextType.onboarding
        labels = [a.label for a in response.suggested_actions]
        assert any("schedule" in l.lower() for l in labels)

    @pytest.mark.asyncio
    @patch("app.services.agent_service.AgentService._call_llm_with_tools", new_callable=AsyncMock)
    async def test_client_with_profile_scheduling_proceeds_normally(
        self, mock_llm, service
    ):
        """Client with client_profile gets scheduling flow, no redirect."""
        mock_llm.return_value = "Here are your available times: Monday 9am, Tuesday 1pm."
        auth = ToolAuthContext(user_id=1, role="client", client_id=10, therapist_id=None)

        response = await service.process_message(
            user_message="I'd like to book an appointment",
            conversation_id=None,
            context_type=AgentContextType.general,
            user_id=1,
            history=[],
            auth=auth,
            db=None,
        )

        assert response.context_type == AgentContextType.scheduling

    @pytest.mark.asyncio
    @patch("app.services.agent_service.AgentService._call_llm_with_tools", new_callable=AsyncMock)
    async def test_therapist_scheduling_no_redirect(self, mock_llm, service):
        """Therapist requesting to schedule does not get onboarding redirect."""
        mock_llm.return_value = "I can help schedule for your client."
        auth = ToolAuthContext(user_id=1, role="therapist", client_id=None, therapist_id=5)

        response = await service.process_message(
            user_message="Book an appointment for my client",
            conversation_id=None,
            context_type=AgentContextType.general,
            user_id=1,
            history=[],
            auth=auth,
            db=None,
        )

        assert response.context_type == AgentContextType.scheduling

    @pytest.mark.asyncio
    @patch("app.services.agent_service.AgentService._call_llm_with_tools", new_callable=AsyncMock)
    async def test_onboarded_client_with_therapist_jumps_to_slots(self, mock_llm, service):
        """Onboarded client with assigned therapist gets therapist_id in prompt, no 'which therapist' ask."""
        mock_llm.return_value = "Here are your available times: Monday 9am, Tuesday 1pm."
        auth = ToolAuthContext(
            user_id=1, role="client", client_id=10, therapist_id=7
        )

        await service.process_message(
            user_message="I'd like to schedule an appointment",
            conversation_id=None,
            context_type=AgentContextType.general,
            user_id=1,
            history=[],
            auth=auth,
            db=None,
        )

        call_kwargs = mock_llm.call_args.kwargs
        assert "Use therapist_id 7" in call_kwargs["system_prompt"]
        assert "Do NOT ask which therapist" in call_kwargs["system_prompt"]
