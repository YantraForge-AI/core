"""Tests for the structured event logging system."""

from __future__ import annotations

import json
from datetime import UTC
from pathlib import Path

import pytest

from yantraforge.events import (
    emit_budget_alert,
    emit_heartbeat_executed,
    emit_heartbeat_skip,
    emit_task_blocked,
    emit_task_completed,
    emit_task_started,
)
from yantraforge.events.hooks import reset_logger
from yantraforge.events.logger import EventLogger
from yantraforge.events.schema import VALID_EVENT_TYPES, Event, TokenUsage


@pytest.fixture(autouse=True)
def _reset_singleton() -> None:
    """Reset the module-level logger between tests."""
    reset_logger()


# ── Schema tests ──────────────────────────────────────────────────


class TestEvent:
    def test_create_minimal_event(self) -> None:
        event = Event(event_type="task_started", agent_id="agent-1", agent_role="cto")
        assert event.event_type == "task_started"
        assert event.agent_id == "agent-1"
        assert event.event_id  # auto-generated UUID
        assert event.timestamp  # auto-generated ISO timestamp

    def test_invalid_event_type_raises(self) -> None:
        with pytest.raises(ValueError, match="Invalid event_type"):
            Event(event_type="not_a_real_event", agent_id="a", agent_role="r")  # type: ignore[arg-type]

    def test_to_dict_excludes_none_token_usage(self) -> None:
        event = Event(event_type="task_started", agent_id="a", agent_role="r")
        d = event.to_dict()
        assert "token_usage" not in d

    def test_to_dict_includes_token_usage_when_set(self) -> None:
        usage = TokenUsage(input=100, output=50, cost_cents=0.25)
        event = Event(
            event_type="task_completed",
            agent_id="a",
            agent_role="r",
            token_usage=usage,
        )
        d = event.to_dict()
        assert d["token_usage"] == {"input": 100, "output": 50, "cost_cents": 0.25}

    def test_to_dict_is_json_serializable(self) -> None:
        event = Event(
            event_type="heartbeat_executed",
            agent_id="a",
            agent_role="r",
            metadata={"tasks_processed": 3},
        )
        serialized = json.dumps(event.to_dict())
        assert '"heartbeat_executed"' in serialized

    def test_all_16_event_types_valid(self) -> None:
        assert len(VALID_EVENT_TYPES) == 16


class TestTokenUsage:
    def test_frozen(self) -> None:
        usage = TokenUsage(input=10, output=20, cost_cents=0.5)
        with pytest.raises(AttributeError):
            usage.input = 99  # type: ignore[misc]


# ── Logger tests ──────────────────────────────────────────────────


class TestEventLogger:
    def test_emit_creates_jsonl_file(self, tmp_path: Path) -> None:
        logger = EventLogger(events_dir=tmp_path)
        event = Event(event_type="task_started", agent_id="a", agent_role="r")
        filepath = logger.emit(event)
        assert filepath.exists()
        assert filepath.suffix == ".jsonl"

    def test_emit_writes_valid_json_line(self, tmp_path: Path) -> None:
        logger = EventLogger(events_dir=tmp_path)
        event = Event(
            event_type="task_completed",
            agent_id="agent-1",
            agent_role="engineering_lead",
            metadata={"lines_changed": 42},
        )
        filepath = logger.emit(event)
        lines = filepath.read_text().strip().split("\n")
        assert len(lines) == 1
        parsed = json.loads(lines[0])
        assert parsed["event_type"] == "task_completed"
        assert parsed["metadata"]["lines_changed"] == 42

    def test_emit_appends_multiple_events(self, tmp_path: Path) -> None:
        logger = EventLogger(events_dir=tmp_path)
        for i in range(5):
            event = Event(
                event_type="heartbeat_executed",
                agent_id=f"agent-{i}",
                agent_role="r",
            )
            logger.emit(event)
        files = list(tmp_path.glob("*.jsonl"))
        assert len(files) == 1
        lines = files[0].read_text().strip().split("\n")
        assert len(lines) == 5

    def test_read_events_returns_list(self, tmp_path: Path) -> None:
        logger = EventLogger(events_dir=tmp_path)
        event = Event(event_type="budget_alert", agent_id="a", agent_role="r")
        logger.emit(event)
        from datetime import datetime

        today = datetime.now(UTC).strftime("%Y-%m-%d")
        events = logger.read_events(today)
        assert len(events) == 1
        assert events[0]["event_type"] == "budget_alert"

    def test_read_events_empty_date(self, tmp_path: Path) -> None:
        logger = EventLogger(events_dir=tmp_path)
        events = logger.read_events("1999-01-01")
        assert events == []


# ── Hook tests ────────────────────────────────────────────────────


class TestHooks:
    def test_emit_task_started(self, tmp_path: Path) -> None:
        event = emit_task_started(
            "agent-1",
            "cto",
            "task-123",
            task_type="feature",
            priority="high",
            parent_id="parent-1",
            events_dir=tmp_path,
        )
        assert event.event_type == "task_started"
        assert event.metadata["task_type"] == "feature"

    def test_emit_task_completed_with_token_usage(self, tmp_path: Path) -> None:
        usage = TokenUsage(input=500, output=200, cost_cents=1.5)
        event = emit_task_completed(
            "agent-1",
            "engineering_lead",
            "task-456",
            duration_seconds=120.5,
            lines_changed=42,
            token_usage=usage,
            events_dir=tmp_path,
        )
        assert event.event_type == "task_completed"
        assert event.token_usage is not None
        assert event.token_usage.cost_cents == 1.5

    def test_emit_task_blocked(self, tmp_path: Path) -> None:
        event = emit_task_blocked(
            "agent-2",
            "backend_engineer",
            "task-789",
            blocker_type="dependency",
            blocker_agent_id="agent-1",
            events_dir=tmp_path,
        )
        assert event.event_type == "task_blocked"
        assert event.metadata["blocker_type"] == "dependency"

    def test_emit_heartbeat_executed(self, tmp_path: Path) -> None:
        event = emit_heartbeat_executed(
            "agent-1",
            "coo",
            duration_seconds=45.0,
            tasks_processed=3,
            tasks_created=1,
            events_dir=tmp_path,
        )
        assert event.event_type == "heartbeat_executed"
        assert event.metadata["tasks_processed"] == 3

    def test_emit_heartbeat_skip(self, tmp_path: Path) -> None:
        event = emit_heartbeat_skip(
            "agent-1",
            "cmo",
            reason="no_assignments",
            events_dir=tmp_path,
        )
        assert event.event_type == "heartbeat_skip"
        assert event.metadata["reason"] == "no_assignments"

    def test_emit_budget_alert(self, tmp_path: Path) -> None:
        event = emit_budget_alert(
            "agent-1",
            "cto",
            current_spend=85.0,
            cap=100.0,
            percent_used=85.0,
            events_dir=tmp_path,
        )
        assert event.event_type == "budget_alert"
        assert event.metadata["percent_used"] == 85.0

    def test_hooks_write_to_jsonl(self, tmp_path: Path) -> None:
        emit_task_started("a", "r", "t1", events_dir=tmp_path)
        emit_task_completed("a", "r", "t1", events_dir=tmp_path)
        emit_task_blocked("a", "r", "t2", events_dir=tmp_path)
        files = list(tmp_path.glob("*.jsonl"))
        assert len(files) == 1
        lines = files[0].read_text().strip().split("\n")
        assert len(lines) == 3
        types = [json.loads(line)["event_type"] for line in lines]
        assert types == ["task_started", "task_completed", "task_blocked"]
