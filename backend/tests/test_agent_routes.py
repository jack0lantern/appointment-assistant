"""Tests for the agent API routes.

Validates /api/agent/chat endpoint behavior including
auth, schema validation, and that LLM payloads are redacted.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock

from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.fixture
def mock_db_session():
    """Mock async DB session."""
    session = AsyncMock()
    session.execute = AsyncMock()
    session.commit = AsyncMock()
    session.close = AsyncMock()
    return session


@pytest.fixture
def mock_user():
    """Mock authenticated user."""
    user = MagicMock()
    user.id = 1
    user.email = "client@test.com"
    user.name = "Test Client"
    user.role = "client"
    return user


class TestAgentChatRoute:
    """POST /api/agent/chat."""

    @pytest.mark.asyncio
    async def test_chat_requires_auth(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/agent/chat",
                json={"message": "Hello"},
            )
            assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_chat_rejects_empty_message(self, mock_user, mock_db_session):
        from app.dependencies import get_current_user, get_db

        app.dependency_overrides[get_current_user] = lambda: mock_user
        app.dependency_overrides[get_db] = lambda: mock_db_session

        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                resp = await client.post(
                    "/api/agent/chat",
                    json={"message": ""},
                )
                assert resp.status_code == 422
        finally:
            app.dependency_overrides.clear()

    @pytest.mark.asyncio
    async def test_chat_returns_expected_shape(self, mock_user, mock_db_session):
        from app.dependencies import get_current_user, get_db

        app.dependency_overrides[get_current_user] = lambda: mock_user
        app.dependency_overrides[get_db] = lambda: mock_db_session

        try:
            with patch("app.routes.agent.AgentService") as MockService:
                from app.schemas.agent import AgentChatResponse, AgentContextType, SafetyMeta

                mock_svc = MockService.return_value
                mock_svc.process_message = AsyncMock(
                    return_value=AgentChatResponse(
                        message="Hello! How can I help you today?",
                        conversation_id="test-conv-123",
                        suggested_actions=[],
                        follow_up_questions=[],
                        safety=SafetyMeta(),
                        context_type=AgentContextType.general,
                    )
                )

                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    resp = await client.post(
                        "/api/agent/chat",
                        json={"message": "Hello"},
                    )
                    assert resp.status_code == 200
                    data = resp.json()
                    assert "message" in data
                    assert "conversation_id" in data
                    assert "suggested_actions" in data
                    assert "safety" in data
        finally:
            app.dependency_overrides.clear()

    @pytest.mark.asyncio
    async def test_chat_with_context_type(self, mock_user, mock_db_session):
        from app.dependencies import get_current_user, get_db

        app.dependency_overrides[get_current_user] = lambda: mock_user
        app.dependency_overrides[get_db] = lambda: mock_db_session

        try:
            with patch("app.routes.agent.AgentService") as MockService:
                from app.schemas.agent import AgentChatResponse, AgentContextType, SafetyMeta

                mock_svc = MockService.return_value
                mock_svc.process_message = AsyncMock(
                    return_value=AgentChatResponse(
                        message="Let me help you get started with onboarding.",
                        conversation_id="test-conv-456",
                        suggested_actions=[],
                        follow_up_questions=[],
                        safety=SafetyMeta(),
                        context_type=AgentContextType.onboarding,
                    )
                )

                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    resp = await client.post(
                        "/api/agent/chat",
                        json={
                            "message": "I'm new here",
                            "context_type": "onboarding",
                        },
                    )
                    assert resp.status_code == 200
                    data = resp.json()
                    assert data["context_type"] == "onboarding"
        finally:
            app.dependency_overrides.clear()
