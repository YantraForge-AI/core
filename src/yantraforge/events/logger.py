"""JSONL event logger for YantraForge.

Writes one JSON object per line to data/events/YYYY-MM-DD.jsonl.
Append-only, daily rotation by filename convention.
"""

from __future__ import annotations

import json
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from yantraforge.events.schema import Event


class EventLogger:
    """Append-only JSONL writer targeting data/events/.

    Thread-safe via a lock around file writes. Each day gets its own
    file (YYYY-MM-DD.jsonl) for easy rotation and querying.

    Args:
        events_dir: Path to the events directory.
                    Defaults to <project_root>/data/events/.
    """

    def __init__(self, events_dir: Path | str | None = None) -> None:
        if events_dir is None:
            # Default: core/data/events/ relative to this file
            self._dir = Path(__file__).resolve().parents[3] / "data" / "events"
        else:
            self._dir = Path(events_dir)
        self._dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    @property
    def events_dir(self) -> Path:
        """Return the directory where event files are written."""
        return self._dir

    def emit(self, event: Event) -> Path:
        """Write an event to the daily JSONL file.

        Returns the path to the file the event was written to.
        """
        date_str = datetime.now(UTC).strftime("%Y-%m-%d")
        filepath = self._dir / f"{date_str}.jsonl"
        line = json.dumps(event.to_dict(), separators=(",", ":")) + "\n"
        with self._lock, filepath.open("a", encoding="utf-8") as f:
            f.write(line)
        return filepath

    def emit_dict(self, data: dict[str, Any]) -> Path:
        """Write a raw dict as a JSONL line. Use for pre-validated data."""
        date_str = datetime.now(UTC).strftime("%Y-%m-%d")
        filepath = self._dir / f"{date_str}.jsonl"
        line = json.dumps(data, separators=(",", ":")) + "\n"
        with self._lock, filepath.open("a", encoding="utf-8") as f:
            f.write(line)
        return filepath

    def read_events(self, date: str | None = None) -> list[dict[str, Any]]:
        """Read all events for a given date (YYYY-MM-DD). Defaults to today."""
        if date is None:
            date = datetime.now(UTC).strftime("%Y-%m-%d")
        filepath = self._dir / f"{date}.jsonl"
        if not filepath.exists():
            return []
        events: list[dict[str, Any]] = []
        with filepath.open(encoding="utf-8") as f:
            for line in f:
                stripped = line.strip()
                if stripped:
                    events.append(json.loads(stripped))
        return events
