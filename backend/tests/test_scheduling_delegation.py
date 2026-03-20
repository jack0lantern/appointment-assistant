"""Tests for therapist delegation in scheduling.

Therapists can book/cancel appointments on behalf of their own clients.
The therapist-client relationship is validated server-side.
"""

import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

from httpx import ASGITransport, AsyncClient

from app.main import app
from app.services.scheduling_service import book_appointment, cancel_appointment


# ── Helpers ──────────────────────────────────────────────────────────────────

def _make_therapist(therapist_id: int = 1):
    t = MagicMock()
    t.id = therapist_id
    return t


def _make_client(client_id: int = 10, therapist_id: int = 1):
    c = MagicMock()
    c.id = client_id
    c.therapist_id = therapist_id
    return c


def _make_session_obj(session_id: int = 100, client_id: int = 10,
                       therapist_id: int = 1, status: str = "scheduled"):
    s = MagicMock()
    s.id = session_id
    s.client_id = client_id
    s.therapist_id = therapist_id
    s.status = status
    return s


def _mock_scalar_one_or_none(value):
    result = MagicMock()
    result.scalar_one_or_none.return_value = value
    return result


def _mock_scalars_all(values):
    result = MagicMock()
    result.scalars.return_value.all.return_value = values
    return result


# ── Service: book_appointment (therapist delegation) ────────────────────────

class TestBookAppointmentTherapistDelegation:
    """Therapist books on behalf of their client."""

    @pytest.mark.asyncio
    async def test_therapist_can_book_for_own_client(self):
        """Therapist with valid relationship can book for client."""
        client = _make_client(client_id=10, therapist_id=1)
        therapist = _make_therapist(therapist_id=1)

        db = AsyncMock()
        # execute calls: client lookup, relationship check, therapist lookup, count, then commit
        db.execute = AsyncMock(side_effect=[
            _mock_scalar_one_or_none(client),      # client exists
            _mock_scalar_one_or_none(client),      # relationship check (client.therapist_id == therapist_id)
            _mock_scalar_one_or_none(therapist),   # therapist exists
            _mock_scalars_all([]),                  # existing session count
        ])
        db.commit = AsyncMock()
        db.refresh = AsyncMock()

        result = await book_appointment(
            db=db,
            client_id=10,
            therapist_id=1,
            slot_id="slot-1-1",
            acting_therapist_id=1,
        )
        assert result["status"] == "confirmed"
        assert result["slot_id"] == "slot-1-1"

    @pytest.mark.asyncio
    async def test_therapist_cannot_book_for_other_therapists_client(self):
        """Therapist 2 cannot book for a client belonging to Therapist 1."""
        client = _make_client(client_id=10, therapist_id=1)

        db = AsyncMock()
        db.execute = AsyncMock(side_effect=[
            _mock_scalar_one_or_none(client),      # client exists
            _mock_scalar_one_or_none(None),         # relationship check fails
        ])

        with pytest.raises(ValueError, match="not authorized"):
            await book_appointment(
                db=db,
                client_id=10,
                therapist_id=1,
                slot_id="slot-1-1",
                acting_therapist_id=2,  # Different therapist
            )

    @pytest.mark.asyncio
    async def test_client_booking_unchanged(self):
        """Normal client booking (no acting_therapist_id) still works."""
        client = _make_client(client_id=10, therapist_id=1)
        therapist = _make_therapist(therapist_id=1)

        db = AsyncMock()
        db.execute = AsyncMock(side_effect=[
            _mock_scalar_one_or_none(client),
            _mock_scalar_one_or_none(therapist),
            _mock_scalars_all([]),
        ])
        db.commit = AsyncMock()
        db.refresh = AsyncMock()

        result = await book_appointment(
            db=db,
            client_id=10,
            therapist_id=1,
            slot_id="slot-1-1",
        )
        assert result["status"] == "confirmed"


# ── Service: cancel_appointment (therapist delegation) ──────────────────────

class TestCancelAppointmentTherapistDelegation:
    """Therapist cancels on behalf of their client."""

    @pytest.mark.asyncio
    async def test_therapist_can_cancel_own_clients_session(self):
        """Therapist can cancel a session for their own client."""
        session_obj = _make_session_obj(
            session_id=100, client_id=10, therapist_id=1, status="scheduled"
        )

        db = AsyncMock()
        db.execute = AsyncMock(return_value=_mock_scalar_one_or_none(session_obj))
        db.commit = AsyncMock()

        result = await cancel_appointment(
            db=db,
            session_id=100,
            client_id=10,
            acting_therapist_id=1,
        )
        assert result["status"] == "cancelled"

    @pytest.mark.asyncio
    async def test_therapist_cannot_cancel_other_therapists_session(self):
        """Therapist 2 cannot cancel Therapist 1's client's session."""
        session_obj = _make_session_obj(
            session_id=100, client_id=10, therapist_id=1, status="scheduled"
        )

        db = AsyncMock()
        db.execute = AsyncMock(return_value=_mock_scalar_one_or_none(session_obj))

        with pytest.raises(ValueError, match="not authorized"):
            await cancel_appointment(
                db=db,
                session_id=100,
                client_id=10,
                acting_therapist_id=2,
            )

    @pytest.mark.asyncio
    async def test_client_cancel_unchanged(self):
        """Normal client cancel (no acting_therapist_id) still works."""
        session_obj = _make_session_obj(
            session_id=100, client_id=10, therapist_id=1, status="scheduled"
        )

        db = AsyncMock()
        db.execute = AsyncMock(return_value=_mock_scalar_one_or_none(session_obj))
        db.commit = AsyncMock()

        result = await cancel_appointment(
            db=db,
            session_id=100,
            client_id=10,
        )
        assert result["status"] == "cancelled"


# ── Routes: therapist delegation ────────────────────────────────────────────

def _mock_therapist_user(therapist_id: int = 1):
    """Mock a therapist user for route tests."""
    user = MagicMock()
    user.id = 1
    user.email = "therapist@test.com"
    user.name = "Dr. Smith"
    user.role = "therapist"
    user.client_profile = None
    user.therapist_profile = MagicMock()
    user.therapist_profile.id = therapist_id
    user.therapist_profile.clients = []
    return user


def _mock_client_user(client_id: int = 10):
    """Mock a client user for route tests."""
    user = MagicMock()
    user.id = 2
    user.email = "client@test.com"
    user.name = "Test Client"
    user.role = "client"
    user.therapist_profile = None
    user.client_profile = MagicMock()
    user.client_profile.id = client_id
    return user


class TestBookRouteTherapistDelegation:
    """POST /api/agent/scheduling/book — therapist delegation."""

    @pytest.mark.asyncio
    async def test_therapist_can_book_with_client_id(self):
        from app.dependencies import get_current_user, get_db

        therapist_user = _mock_therapist_user(therapist_id=1)
        db = AsyncMock()
        app.dependency_overrides[get_current_user] = lambda: therapist_user
        app.dependency_overrides[get_db] = lambda: db

        try:
            with patch("app.routes.agent_scheduling.book_appointment") as mock_book:
                mock_book.return_value = {
                    "session_id": 100,
                    "status": "confirmed",
                    "slot_id": "slot-1-1",
                    "session_date": "2026-03-25T09:00:00+00:00",
                    "duration_minutes": 50,
                }
                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    resp = await client.post(
                        "/api/agent/scheduling/book",
                        json={
                            "therapist_id": 1,
                            "slot_id": "slot-1-1",
                            "client_id": 10,
                        },
                    )
                    assert resp.status_code == 200
                    # Verify acting_therapist_id was passed
                    mock_book.assert_called_once()
                    call_kwargs = mock_book.call_args.kwargs
                    assert call_kwargs["acting_therapist_id"] == 1
                    assert call_kwargs["client_id"] == 10
        finally:
            app.dependency_overrides.clear()

    @pytest.mark.asyncio
    async def test_therapist_must_provide_client_id(self):
        """Therapist booking without client_id should fail."""
        from app.dependencies import get_current_user, get_db

        therapist_user = _mock_therapist_user()
        db = AsyncMock()
        app.dependency_overrides[get_current_user] = lambda: therapist_user
        app.dependency_overrides[get_db] = lambda: db

        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                resp = await client.post(
                    "/api/agent/scheduling/book",
                    json={
                        "therapist_id": 1,
                        "slot_id": "slot-1-1",
                        # No client_id — therapist can't book without specifying who
                    },
                )
                assert resp.status_code == 400
        finally:
            app.dependency_overrides.clear()

    @pytest.mark.asyncio
    async def test_client_booking_still_ignores_client_id_field(self):
        """Client user: client_id comes from auth, request body client_id is ignored."""
        from app.dependencies import get_current_user, get_db

        client_user = _mock_client_user(client_id=10)
        db = AsyncMock()
        app.dependency_overrides[get_current_user] = lambda: client_user
        app.dependency_overrides[get_db] = lambda: db

        try:
            with patch("app.routes.agent_scheduling.book_appointment") as mock_book:
                mock_book.return_value = {
                    "session_id": 101,
                    "status": "confirmed",
                    "slot_id": "slot-1-2",
                    "session_date": "2026-03-25T13:00:00+00:00",
                    "duration_minutes": 50,
                }
                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    resp = await client.post(
                        "/api/agent/scheduling/book",
                        json={
                            "therapist_id": 1,
                            "slot_id": "slot-1-2",
                            "client_id": 999,  # Attempt to spoof — should be ignored
                        },
                    )
                    assert resp.status_code == 200
                    call_kwargs = mock_book.call_args.kwargs
                    # Client ID comes from auth (10), not the spoofed value (999)
                    assert call_kwargs["client_id"] == 10
                    assert "acting_therapist_id" not in call_kwargs or call_kwargs.get("acting_therapist_id") is None
        finally:
            app.dependency_overrides.clear()


class TestCancelRouteTherapistDelegation:
    """POST /api/agent/scheduling/cancel — therapist delegation."""

    @pytest.mark.asyncio
    async def test_therapist_can_cancel_with_client_id(self):
        from app.dependencies import get_current_user, get_db

        therapist_user = _mock_therapist_user(therapist_id=1)
        db = AsyncMock()
        app.dependency_overrides[get_current_user] = lambda: therapist_user
        app.dependency_overrides[get_db] = lambda: db

        try:
            with patch("app.routes.agent_scheduling.cancel_appointment") as mock_cancel:
                mock_cancel.return_value = {
                    "session_id": 100,
                    "status": "cancelled",
                }
                transport = ASGITransport(app=app)
                async with AsyncClient(transport=transport, base_url="http://test") as client:
                    resp = await client.post(
                        "/api/agent/scheduling/cancel",
                        json={
                            "session_id": 100,
                            "client_id": 10,
                        },
                    )
                    assert resp.status_code == 200
                    call_kwargs = mock_cancel.call_args.kwargs
                    assert call_kwargs["acting_therapist_id"] == 1
                    assert call_kwargs["client_id"] == 10
        finally:
            app.dependency_overrides.clear()

    @pytest.mark.asyncio
    async def test_therapist_must_provide_client_id_for_cancel(self):
        """Therapist cancel without client_id should fail."""
        from app.dependencies import get_current_user, get_db

        therapist_user = _mock_therapist_user()
        db = AsyncMock()
        app.dependency_overrides[get_current_user] = lambda: therapist_user
        app.dependency_overrides[get_db] = lambda: db

        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                resp = await client.post(
                    "/api/agent/scheduling/cancel",
                    json={
                        "session_id": 100,
                        # No client_id
                    },
                )
                assert resp.status_code == 400
        finally:
            app.dependency_overrides.clear()
