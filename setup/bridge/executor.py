from __future__ import annotations

import json
import os
import subprocess
import sys
import pwd
from dataclasses import dataclass
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from setup.state.schema import DEFAULT_STATE, normalize_state


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SETUP_ROOT = PROJECT_ROOT / "setup"
LEGACY_STATE_PATH = SETUP_ROOT / "state" / "state.json"
ENGINE_PATH = SETUP_ROOT / "backend" / "engine.sh"


def _default_cache_home() -> Path:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        try:
            return Path(pwd.getpwnam(sudo_user).pw_dir) / ".cache"
        except KeyError:
            pass
    xdg_cache = os.environ.get("XDG_CACHE_HOME")
    if xdg_cache:
        return Path(xdg_cache)
    return Path.home() / ".cache"


def default_state_path() -> Path:
    return _default_cache_home() / "arctyx" / "state.json"


def _deep_copy_state(state: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(state))


@dataclass
class StateStore:
    path: Path | None = None

    def __post_init__(self) -> None:
        if self.path is None:
            self.path = default_state_path()

    def exists(self) -> bool:
        assert self.path is not None
        return self.path.exists()

    def _migrate_legacy_state(self) -> None:
        assert self.path is not None
        if self.path.exists() or not LEGACY_STATE_PATH.exists():
            return
        legacy_state = normalize_state(json.loads(LEGACY_STATE_PATH.read_text()))
        self.save(legacy_state)

    def ensure(self) -> dict[str, Any]:
        self._migrate_legacy_state()
        assert self.path is not None
        if not self.path.exists():
            self.save(DEFAULT_STATE)
        return self.load()

    def load(self) -> dict[str, Any]:
        self._migrate_legacy_state()
        assert self.path is not None
        if not self.path.exists():
            raise FileNotFoundError(f"State file not found: {self.path}")
        return normalize_state(json.loads(self.path.read_text()))

    def save(self, state: dict[str, Any]) -> None:
        assert self.path is not None
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(normalize_state(state), indent=2) + "\n")

    def update(self, updater) -> dict[str, Any]:
        state = self.load()
        new_state = _deep_copy_state(state)
        updater(new_state)
        self.save(new_state)
        return new_state


@dataclass
class BackendExecutor:
    state_path: Path | None = None
    engine_path: Path = ENGINE_PATH

    def __post_init__(self) -> None:
        if self.state_path is None:
            self.state_path = default_state_path()

    def run(self, action: str = "apply", check: bool = True) -> subprocess.CompletedProcess[str]:
        assert self.state_path is not None
        return subprocess.run(
            ["bash", str(self.engine_path), str(self.state_path), action],
            text=True,
            capture_output=False,
            check=check,
        )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run the Bash backend engine from JSON state.")
    parser.add_argument("action", nargs="?", default="plan", choices=["apply", "plan", "rollback", "uninstall"])
    parser.add_argument("--state", default=str(default_state_path()))
    args = parser.parse_args()

    executor = BackendExecutor(state_path=Path(args.state))
    executor.run(args.action)
