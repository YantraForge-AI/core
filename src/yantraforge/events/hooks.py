"""Convenience functions for emitting lifecycle events.

These are the primary integration points for agents. Each function
constructs and emits an Event with the correct event_type and metadata.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from yantraforge.events.logger import EventLogger
from yantraforge.events.schema import Event, EventType, TokenUsage

# Module-level singleton — initialized on first use
_logger: EventLogger | None = None


def get_logger(events_dir: Path | str | None = None) -> EventLogger:
    """Return the module-level EventLogger, creating it if needed."""
    global _logger
    if _logger is None:
        _logger = EventLogger(events_dir=events_dir)
    return _logger


def reset_logger() -> None:
    """Reset the module-level logger. Primarily for testing."""
    global _logger
    _logger = None


def _emit(
    event_type: EventType,
    agent_id: str,
    agent_role: str,
    *,
    task_id: str = "",
    duration_seconds: float = 0.0,
    token_usage: TokenUsage | None = None,
    metadata: dict[str, Any] | None = None,
    events_dir: Path | str | None = None,
    **kwargs: Any,
) -> Event:
    """Internal helper: build and emit an event."""
    event = Event(
        event_type=event_type,
        agent_id=agent_id,
        agent_role=agent_role,
        task_id=task_id,
        duration_seconds=duration_seconds,
        token_usage=token_usage,
        metadata=metadata or {},
        **kwargs,
    )
    get_logger(events_dir).emit(event)
    return event


# ── Task lifecycle ─────────────────────────────────────────────────


def emit_task_started(
    agent_id: str,
    agent_role: str,
    task_id: str,
    *,
    task_type: str = "",
    priority: str = "",
    parent_id: str = "",
    events_dir: Path | str | None = None,
) -> Event:
    """Emit when an agent checks out a task."""
    return _emit(
        "task_started",
        agent_id,
        agent_role,
        task_id=task_id,
        metadata={"task_type": task_type, "priority": priority, "parent_id": parent_id},
        events_dir=events_dir,
    )


def emit_task_completed(
    agent_id: str,
    agent_role: str,
    task_id: str,
    *,
    duration_seconds: float = 0.0,
    deliverable_type: str = "",
    lines_changed: int = 0,
    files_touched: int = 0,
    token_usage: TokenUsage | None = None,
    events_dir: Path | str | None = None,
) -> Event:
    """Emit when an agent marks a task done or in_review."""
    return _emit(
        "task_completed",
        agent_id,
        agent_role,
        task_id=task_id,
        duration_seconds=duration_seconds,
        token_usage=token_usage,
        metadata={
            "deliverable_type": deliverable_type,
            "lines_changed": lines_changed,
            "files_touched": files_touched,
            "duration_seconds": duration_seconds,
        },
        events_dir=events_dir,
    )


def emit_task_blocked(
    agent_id: str,
    agent_role: str,
    task_id: str,
    *,
    blocker_type: str = "",
    blocker_agent_id: str = "",
    events_dir: Path | str | None = None,
) -> Event:
    """Emit when an agent marks a task blocked."""
    return _emit(
        "task_blocked",
        agent_id,
        agent_role,
        task_id=task_id,
        metadata={"blocker_type": blocker_type, "blocker_agent_id": blocker_agent_id},
        events_dir=events_dir,
    )


# ── Heartbeat lifecycle ───────────────────────────────────────────


def emit_heartbeat_executed(
    agent_id: str,
    agent_role: str,
    *,
    duration_seconds: float = 0.0,
    tasks_processed: int = 0,
    tasks_created: int = 0,
    events_dir: Path | str | None = None,
) -> Event:
    """Emit at the end of every heartbeat."""
    return _emit(
        "heartbeat_executed",
        agent_id,
        agent_role,
        duration_seconds=duration_seconds,
        metadata={
            "tasks_processed": tasks_processed,
            "tasks_created": tasks_created,
            "duration_seconds": duration_seconds,
        },
        events_dir=events_dir,
    )


def emit_heartbeat_skip(
    agent_id: str,
    agent_role: str,
    *,
    reason: str = "",
    events_dir: Path | str | None = None,
) -> Event:
    """Emit when a heartbeat is skipped."""
    return _emit(
        "heartbeat_skip",
        agent_id,
        agent_role,
        metadata={"reason": reason},
        events_dir=events_dir,
    )


# ── Budget ─────────────────────────────────────────────────────────


def emit_budget_alert(
    agent_id: str,
    agent_role: str,
    *,
    current_spend: float,
    cap: float,
    percent_used: float,
    events_dir: Path | str | None = None,
) -> Event:
    """Emit when an agent hits 80%+ budget."""
    return _emit(
        "budget_alert",
        agent_id,
        agent_role,
        metadata={
            "agent_id": agent_id,
            "current_spend": current_spend,
            "cap": cap,
            "percent_used": percent_used,
        },
        events_dir=events_dir,
    )
