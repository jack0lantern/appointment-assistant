"""Tests for the scheduling service."""

import pytest
from datetime import datetime, timezone

from app.services.scheduling_service import generate_demo_slots


class TestDemoSlots:
    """Demo slot generation."""

    def test_generates_slots(self):
        slots = generate_demo_slots(therapist_id=1)
        assert len(slots) > 0

    def test_slots_have_required_fields(self):
        slots = generate_demo_slots(therapist_id=1)
        for slot in slots:
            assert "id" in slot
            assert "therapist_id" in slot
            assert "start_time" in slot
            assert "end_time" in slot
            assert "duration_minutes" in slot
            assert "available" in slot

    def test_slots_skip_weekends(self):
        # Start on a Friday so we can check weekends are skipped
        friday = datetime(2026, 3, 20, tzinfo=timezone.utc)  # a Friday
        slots = generate_demo_slots(therapist_id=1, start_date=friday, days_ahead=4)
        for slot in slots:
            dt = datetime.fromisoformat(slot["start_time"])
            assert dt.weekday() < 5, f"Slot on weekend: {dt}"

    def test_slots_have_stable_ids(self):
        slots = generate_demo_slots(therapist_id=1)
        ids = [s["id"] for s in slots]
        assert len(ids) == len(set(ids)), "Slot IDs should be unique"

    def test_slots_include_therapist_id(self):
        slots = generate_demo_slots(therapist_id=42)
        for slot in slots:
            assert slot["therapist_id"] == 42

    def test_duration_is_50_minutes(self):
        slots = generate_demo_slots(therapist_id=1)
        for slot in slots:
            assert slot["duration_minutes"] == 50
