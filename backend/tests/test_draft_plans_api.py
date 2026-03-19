"""Tests for the draft-plan dashboard feature.

Covers two behaviours:
1. A newly generated plan (status='draft') appears in GET /api/treatment-plans/draft
2. Approving a plan via POST /api/treatment-plans/{id}/approve removes it from that list
"""
import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.dependencies import get_db, require_therapist
from app.models.user import User
from app.models.therapist import Therapist
from app.models.client import Client
from app.models.treatment_plan import TreatmentPlan


# ── DB result helpers ─────────────────────────────────────────────────────────

def _scalars_all(*items):
    """Mimic db.execute(...).scalars().all() returning items."""
    r = MagicMock()
    r.scalars.return_value.all.return_value = list(items)
    return r


def _scalar_one(item):
    """Mimic db.execute(...).scalar_one_or_none() returning item."""
    r = MagicMock()
    r.scalar_one_or_none.return_value = item
    return r


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def therapist_user():
    therapist = MagicMock(spec=Therapist)
    therapist.id = 1
    user = MagicMock(spec=User)
    user.id = 1
    user.role = "therapist"
    user.therapist_profile = therapist
    return user


@pytest.fixture
def mock_client():
    c = MagicMock(spec=Client)
    c.id = 1
    c.name = "Alice"
    c.therapist_id = 1
    return c


@pytest.fixture
def draft_plan(mock_client):
    plan = MagicMock(spec=TreatmentPlan)
    plan.id = 10
    plan.client_id = 1
    plan.therapist_id = 1
    plan.status = "draft"
    plan.current_version_id = 5
    plan.created_at = datetime(2024, 3, 1, tzinfo=timezone.utc)
    plan.client = mock_client
    return plan


@pytest.fixture
def mock_db():
    db = AsyncMock()
    db.commit = AsyncMock()
    db.refresh = AsyncMock()
    return db


@pytest.fixture(autouse=True)
def _override_deps(therapist_user, mock_db):
    """Replace DB and auth dependencies for every test in this module."""
    async def _therapist():
        return therapist_user

    async def _db():
        yield mock_db

    app.dependency_overrides[require_therapist] = _therapist
    app.dependency_overrides[get_db] = _db
    yield
    app.dependency_overrides.clear()


# ── Tests ─────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_draft_plan_appears_in_list(mock_db, draft_plan):
    """A plan with status='draft' must show up in the dashboard draft list."""
    mock_db.execute.return_value = _scalars_all(draft_plan)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/treatment-plans/draft")

    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    entry = data[0]
    assert entry["plan_id"] == draft_plan.id
    assert entry["client_id"] == draft_plan.client_id
    assert entry["client_name"] == draft_plan.client.name


@pytest.mark.asyncio
async def test_multiple_draft_plans_ordered_oldest_first(mock_db, mock_client):
    """Multiple draft plans are returned oldest-first (backend orders by created_at asc)."""
    older = MagicMock(spec=TreatmentPlan)
    older.id = 7
    older.client_id = 1
    older.therapist_id = 1
    older.status = "draft"
    older.current_version_id = None
    older.created_at = datetime(2024, 1, 10, tzinfo=timezone.utc)
    older.client = mock_client

    newer = MagicMock(spec=TreatmentPlan)
    newer.id = 11
    newer.client_id = 1
    newer.therapist_id = 1
    newer.status = "draft"
    newer.current_version_id = None
    newer.created_at = datetime(2024, 6, 5, tzinfo=timezone.utc)
    newer.client = mock_client

    # DB already returns them in the correct order (route orders by created_at asc)
    mock_db.execute.return_value = _scalars_all(older, newer)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/treatment-plans/draft")

    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    assert data[0]["plan_id"] == older.id
    assert data[1]["plan_id"] == newer.id


@pytest.mark.asyncio
async def test_no_draft_plans_returns_empty_list(mock_db):
    """When all plans are approved, the draft endpoint returns an empty list."""
    mock_db.execute.return_value = _scalars_all()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.get("/api/treatment-plans/draft")

    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_approving_plan_removes_it_from_draft_list(mock_db, draft_plan):
    """POST approve mutates plan.status to 'approved'; a subsequent draft list call excludes it."""
    # Step 1 — approve the plan.
    # Two DB hits inside approve_plan:
    #   1. _get_plan_for_therapist  →  scalar_one_or_none returns the plan
    #   2. unacknowledged safety flag check  →  scalars().all() returns []
    mock_db.execute.side_effect = [
        _scalar_one(draft_plan),
        _scalars_all(),
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        approve_resp = await ac.post(f"/api/treatment-plans/{draft_plan.id}/approve")

    assert approve_resp.status_code == 200
    assert draft_plan.status == "approved"  # route mutated the mock attribute

    # Step 2 — draft list is now empty because the plan is approved.
    mock_db.execute.side_effect = None
    mock_db.execute.return_value = _scalars_all()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        draft_resp = await ac.get("/api/treatment-plans/draft")

    assert draft_resp.status_code == 200
    assert draft_resp.json() == []


@pytest.mark.asyncio
async def test_approve_with_unacknowledged_safety_flags_blocks(mock_db, draft_plan):
    """Approving a plan with unacknowledged safety flags returns 400, leaving the plan in draft."""
    from app.models.safety_flag import SafetyFlag

    unacked_flag = MagicMock(spec=SafetyFlag)
    mock_db.execute.side_effect = [
        _scalar_one(draft_plan),
        _scalars_all(unacked_flag),  # one unacknowledged flag
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        resp = await ac.post(f"/api/treatment-plans/{draft_plan.id}/approve")

    assert resp.status_code == 400
    # Plan was NOT approved — still draft
    assert draft_plan.status == "draft"
