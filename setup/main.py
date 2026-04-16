from __future__ import annotations

import argparse
import subprocess
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from setup.bridge.executor import BackendExecutor, StateStore


def run_app(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Arctyx modular installer")
    parser.add_argument(
        "--action",
        default="wizard",
        choices=["wizard", "plan", "apply", "rollback", "uninstall"],
        help="Wizard launches the interactive Meowrch-style installer; other actions run the backend directly.",
    )
    parser.add_argument("--state", default=None, help="Path to state JSON file")
    args = parser.parse_args(argv)

    state_store = StateStore()
    if args.state:
        state_store.path = Path(args.state)
    state_store.ensure()

    executor = BackendExecutor(state_path=Path(state_store.path))

    def _run_backend_action(action: str, env_vars: dict[str, str] | None = None) -> int:
        if shutil.which("jq") is None:
            print("Arctyx backend needs `jq` to read the JSON state. Please install `jq` first, then run again.")
            return 1
        try:
            executor.run(action, env_vars=env_vars)
        except KeyboardInterrupt:
            print("\nArctyx backend action was cancelled by the user.")
            return 130
        except subprocess.CalledProcessError as exc:
            print(f"Arctyx backend action failed with exit code {exc.returncode}.")
            return exc.returncode or 1
        except Exception as exc:
            print(f"Arctyx backend action failed: {exc}")
            return 1
        return 0

    if args.action != "wizard":
        return _run_backend_action(args.action)

    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Arctyx wizard needs an interactive TTY. Use --action plan/apply for non-interactive runs.")
        return 1

    try:
        from setup.ui.wizard import WizardInstaller
    except ModuleNotFoundError as exc:
        if exc.name == "curses":
            print("The Python curses module is unavailable in this environment.")
            return 1
        raise

    app = WizardInstaller(state_path=state_store.path)
    result = app.run()
    if result in {"apply", "plan", "rollback", "uninstall"}:
        env = {}
        if hasattr(app, "state") and getattr(app.state, "de_auto_swap", False):
            env["DE_AUTO_SWAP"] = "yes"
        exit_code = _run_backend_action(result, env_vars=env)
        should_delete = (
            exit_code == 0
            and result == "apply"
            and not app.raw_state.get("profile", {}).get("save", False)
        )
        if should_delete:
            if state_store.path and state_store.path.exists():
                try:
                    state_store.path.unlink()
                except OSError:
                    pass
        return exit_code
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(run_app())
    except KeyboardInterrupt:
        print("\nArctyx was cancelled by the user.")
        raise SystemExit(130)
