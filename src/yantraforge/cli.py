"""YantraForge CLI entry point."""

from __future__ import annotations

import sys


def main() -> None:
    """Entry point for the `yf` command."""
    print(f"yantraforge {__import__('yantraforge').__version__}")
    sys.exit(0)
