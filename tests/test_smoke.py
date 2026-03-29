"""Smoke tests — validates the project skeleton is importable and CLI wired."""

from __future__ import annotations

import subprocess
import sys

import pytest

import yantraforge
from yantraforge.cli import main


def test_version_exists() -> None:
    assert yantraforge.__version__ == "0.1.0"


def test_cli_main_exits_zero() -> None:
    with pytest.raises(SystemExit) as exc_info:
        main()
    assert exc_info.value.code == 0


def test_module_invocation() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "yantraforge"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "yantraforge" in result.stdout
