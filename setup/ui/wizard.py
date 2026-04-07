from __future__ import annotations

import curses
import json
from pathlib import Path

from setup.bridge.executor import StateStore
from setup.state.schema import DEFAULT_STATE, normalize_state
from setup.ui.components import WizardUI
from setup.ui.state import WizardState
from setup.ui.steps import (
    configure_apps_section,
    configure_boot_section,
    configure_desktop_section,
    configure_drivers_section,
    configure_finalize_section,
    configure_login_section,
    configure_packages_section,
    configure_user_section,
    step_section_menu,
)


class WizardInstaller:
    def __init__(self, state_path: Path | None = None) -> None:
        self.state_store = StateStore(path=state_path or StateStore().path)
        self.had_existing_state = self.state_store.exists()
        self.raw_state = self.state_store.ensure()
        self.state = WizardState.from_json_state(self.raw_state)

    def _reset_state(self) -> None:
        self.raw_state = normalize_state(json.loads(json.dumps(DEFAULT_STATE)))
        self.state = WizardState.from_json_state(self.raw_state)
        self.save()

    def _has_saved_progress(self) -> bool:
        current = normalize_state(json.loads(json.dumps(self.raw_state)))
        baseline = normalize_state(json.loads(json.dumps(DEFAULT_STATE)))
        current["workflow"] = baseline["workflow"]
        return current != baseline

    def save(self) -> None:
        updated = self.state.apply_to_json_state(self.raw_state)
        self.state_store.save(updated)

    def run_section(self, ui: WizardUI, section_key: str) -> str | None:
        section_handlers = {
            "user": configure_user_section,
            "packages": configure_packages_section,
            "apps": configure_apps_section,
            "desktop": configure_desktop_section,
            "login": configure_login_section,
            "drivers": configure_drivers_section,
            "boot": configure_boot_section,
        }
        if section_key == "finalize":
            ui.set_step(8, 8)
            result = configure_finalize_section(ui, self.state)
            self.save()
            return result

        ui.set_step(0, 0)
        section_handlers[section_key](ui, self.state)
        self.save()
        return None

    def run_installer(self, ui: WizardUI) -> str:
        while True:
            workflow_choice = ui.show_welcome_screen()
            if workflow_choice == "rollback":
                self.raw_state["workflow"]["action"] = "rollback"
                self.save()
                return "rollback"
            if workflow_choice == "uninstall":
                self.raw_state["workflow"]["action"] = "uninstall"
                self.save()
                return "uninstall"

            if self.had_existing_state:
                resume_choice = ui.ask_resume_state()
                if resume_choice == "__back__":
                    continue
                if resume_choice == "fresh":
                    self._reset_state()
            elif self._has_saved_progress():
                self._reset_state()

            self.raw_state["workflow"]["mode"] = "install"
            self.raw_state["workflow"]["action"] = "plan"
            self.save()

            while True:
                ui.set_step(0, 0)
                section_key = step_section_menu(ui, self.state)
                if section_key == "__back__":
                    break
                result = self.run_section(ui, section_key)
                if result == "apply":
                    self.raw_state["workflow"]["action"] = "apply"
                    self.save()
                    return "apply"
                if result == "back":
                    continue
                if result == "cancel":
                    break

            if self.raw_state["workflow"]["action"] != "apply":
                self.raw_state["workflow"]["action"] = "plan"
                self.save()

    def run(self) -> str:
        def _inner(stdscr: curses.window) -> str:
            ui = WizardUI(stdscr)
            try:
                return self.run_installer(ui)
            except KeyboardInterrupt:
                self.raw_state["workflow"]["action"] = "plan"
                self.save()
                return "cancel"

        return curses.wrapper(_inner)
