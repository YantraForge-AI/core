"""Event schema definitions for YantraForge structured logging.

Defines the 16 event types from the ORG blueprint and the common
event envelope written to data/events/ as JSONL.
"""

from __future__ import annotations

import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from typing import Any, Literal

EventType = Literal[
    "task_started",
    "task_completed",
    "task_blocked",
    "review_submitted",
    "review_overridden",
    "escalation_created",
    "escalation_resolved",
    "cross_team_handoff",
    "cross_team_completed",
    "heartbeat_skip",
    "heartbeat_executed",
    "qa_test_result",
    "prompt_updated",
    "budget_alert",
    "infra_event",
    "knowledge_extracted",
]

VALID_EVENT_TYPES: frozenset[str] = frozenset(EventType.__args__)  # type: ignore[attr-defined]


@dataclass(frozen=True, slots=True)
class TokenUsage:
    """Token consumption for a single event."""

    input: int
    output: int
    cost_cents: float


@dataclass(slots=True)
class Event:
    """Common event envelope for all YantraForge structured events.

    Fields match the schema defined in ORG-blueprint.md §Event Logging.
    """

    event_type: EventType
    agent_id: str
    agent_role: str

    # Optional context fields — populated when available
    team: str = ""
    cxo: str = ""
    task_id: str = ""
    engagement: str = ""
    prompt_version: str = ""
    model_id: str = ""
    duration_seconds: float = 0.0
    token_usage: TokenUsage | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    # Auto-generated fields
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: str = field(
        default_factory=lambda: datetime.now(UTC).isoformat(),
    )

    def __post_init__(self) -> None:
        if self.event_type not in VALID_EVENT_TYPES:
            raise ValueError(
                f"Invalid event_type {self.event_type!r}. "
                f"Must be one of: {sorted(VALID_EVENT_TYPES)}"
            )

    def to_dict(self) -> dict[str, Any]:
        """Serialize to a JSON-compatible dict."""
        d = asdict(self)
        if self.token_usage is None:
            d.pop("token_usage")
        return d
