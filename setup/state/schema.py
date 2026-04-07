from __future__ import annotations

from copy import deepcopy
from typing import Any


DEFAULT_STATE: dict[str, Any] = {
    "workflow": {
        "mode": "install",
        "action": "plan",
        "start_section": 1,
        "continue": True,
    },
    "user": {
        "target": "root",
        "use_current_user": True,
    },
    "packages": {
        "base_enable": True,
        "optimize_mirrors": False,
        "categories": ["core-system", "cli-utils"],
        "shell_choice": "bash",
        "aur_helper": "skip",
        "multilib": False,
        "core_testing": False,
        "extra_testing": False,
        "multilib_testing": False,
        "chaotic_aur": False,
    },
    "apps": {
        "selected": [],
        "ides": [],
        "custom": [],
    },
    "desktop": {
        "primary": "none",
        "sessions": [],
        "profile": "full",
        "custom_packages": [],
    },
    "login": {
        "method": "tty-autologin",
        "display_manager": "none",
        "autologin": False,
        "dm_action": "keep",
        "tty_device": "tty1",
        "autostart": {
            "action": "skip",
            "enabled": False,
            "session": "hyprland",
            "command": "",
            "install_missing": False,
            "install_profile": "core",
        },
    },
    "drivers": {
        "mode": "skip",
        "selected_groups": [],
        "pacman_packages": [],
        "aur_packages": [],
    },
    "boot": {
        "enabled": True,
        "silent": True,
        "os_prober": True,
        "plymouth_action": "skip",
        "bootloader_action": "keep",
        "replace_bootloader": False,
        "bootloader": "grub",
    },
    "profile": {
        "save": False,
        "name": "",
    },
}


def _merge_dict(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _merge_dict(merged[key], value)
        else:
            merged[key] = deepcopy(value)
    return merged


def normalize_state(state: dict[str, Any] | None) -> dict[str, Any]:
    normalized = _merge_dict(DEFAULT_STATE, state or {})

    if normalized["user"].get("use_current_user") and not normalized["user"].get("target"):
        normalized["user"]["target"] = DEFAULT_STATE["user"]["target"]

    for path in (
        ("packages", "categories"),
        ("apps", "selected"),
        ("apps", "ides"),
        ("apps", "custom"),
        ("desktop", "sessions"),
        ("desktop", "custom_packages"),
        ("drivers", "selected_groups"),
        ("drivers", "pacman_packages"),
        ("drivers", "aur_packages"),
    ):
        node = normalized[path[0]]
        if not isinstance(node.get(path[1]), list):
            node[path[1]] = []

    if not normalized["boot"].get("bootloader_action"):
        normalized["boot"]["bootloader_action"] = (
            "replace" if normalized["boot"].get("replace_bootloader") else "keep"
        )

    if not normalized["login"]["autostart"].get("action"):
        normalized["login"]["autostart"]["action"] = (
            "on" if normalized["login"]["autostart"].get("enabled") else "skip"
        )

    return normalized
