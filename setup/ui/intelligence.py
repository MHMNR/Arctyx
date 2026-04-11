from __future__ import annotations

import os
import re
import shutil
import socket
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from setup.ui.state import WizardState, desktop_label


# BUG #36: Detect kernel-bundled NVIDIA packages (CachyOS, XanMod, Liquorix, etc.)
def _detect_kernel_bundled_nvidia() -> list[str]:
    try:
        result = subprocess.run(
            ["pacman", "-Qq"],
            capture_output=True, text=True, check=False
        )
        return [
            p for p in result.stdout.splitlines()
            if re.match(r'^linux-.*nvidia', p)
        ]
    except FileNotFoundError:
        return []


@dataclass
class ReviewReport:
    ready: bool
    validations: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    recommendations: list[str] = field(default_factory=list)


_REVIEW_CACHE: dict[tuple, tuple[float, ReviewReport]] = {}


def _mounted(path: str) -> bool:
    try:
        proc = subprocess.run(["findmnt", "-rn", path], capture_output=True, text=True, check=False)
        return proc.returncode == 0
    except FileNotFoundError:
        return os.path.ismount(path)


def _detect_esp_mount() -> str | None:
    for candidate in ("/boot/efi", "/efi", "/boot"):
        if os.path.isdir(candidate) and _mounted(candidate):
            return candidate
    return None


def _command_success(command: list[str]) -> bool:
    try:
        return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode == 0
    except FileNotFoundError:
        return False


def _pacman_lock_present() -> bool:
    return Path("/var/lib/pacman/db.lck").exists()


def _free_space_gib(path: str) -> float | None:
    try:
        usage = shutil.disk_usage(path)
    except FileNotFoundError:
        return None
    return usage.free / (1024 ** 3)


def _network_available() -> bool:
    targets = [
        ("1.1.1.1", 53),
        ("8.8.8.8", 53),
        ("github.com", 443),
        ("archlinux.org", 443),
    ]
    for host, port in targets:
        try:
            with socket.create_connection((host, port), timeout=0.35):
                return True
        except OSError:
            continue
    return False


def _boot_path_mounted() -> bool:
    return _mounted("/boot")


def _kernel_header_status(state: WizardState) -> tuple[bool | None, str]:
    if state.driver_mode == "skip":
        return None, "Not Required"

    dkms_selected = any(pkg.endswith("-dkms") for pkg in state.driver_packages)
    if not dkms_selected:
        return None, "Not Required"

    uname = ""
    try:
        uname = subprocess.run(["uname", "-r"], capture_output=True, text=True, check=False).stdout.strip()
    except FileNotFoundError:
        return False, "Kernel Unknown"

    header_pkg = "linux-headers"
    if "-zen" in uname:
        header_pkg = "linux-zen-headers"
    elif "-lts" in uname:
        header_pkg = "linux-lts-headers"
    elif "-hardened" in uname:
        header_pkg = "linux-hardened-headers"

    installed = _command_success(["pacman", "-Q", header_pkg])
    return installed, header_pkg


def _review_state_signature(state: WizardState) -> tuple:
    return (
        state.target_user,
        state.shell_choice,
        tuple(state.package_categories),
        state.aur_helper,
        tuple(state.selected_apps),
        tuple(state.selected_ides),
        tuple(state.custom_apps),
        tuple(state.desktop_sessions),
        state.desktop_profile,
        state.login_method,
        state.display_manager,
        state.autologin,
        state.tty_device,
        state.autostart_action,
        state.autostart_enabled,
        state.autostart_session,
        state.autostart_custom_command,
        state.driver_mode,
        tuple(state.driver_groups),
        tuple(state.driver_packages),
        state.boot_splash_mode,
        state.boot_os_prober_action,
        state.bootloader_action,
        state.bootloader_choice,
        state.save_profile,
    )


def build_review_report(state: WizardState) -> ReviewReport:
    signature = _review_state_signature(state)
    cached = _REVIEW_CACHE.get(signature)
    now = time.monotonic()
    if cached and (now - cached[0]) < 5:
        return cached[1]

    validations: list[str] = []
    warnings: list[str] = []
    recommendations: list[str] = []

    is_uefi = os.path.isdir("/sys/firmware/efi")
    esp_mount = _detect_esp_mount()
    os_prober_available = shutil.which("os-prober") is not None
    boot_mounted = _boot_path_mounted()
    pacman_lock = _pacman_lock_present()
    network_ok = _network_available()
    free_gib = _free_space_gib("/")
    header_status, header_detail = _kernel_header_status(state)

    validations.append(f"Firmware: {'UEFI' if is_uefi else 'Legacy BIOS'}")
    validations.append(f"EFI System Partition: {esp_mount or 'Not Mounted'}")
    validations.append(f"/boot Mount: {'Mounted' if boot_mounted else 'Not Mounted'}")
    validations.append(f"OS-Prober: {'Installed' if os_prober_available else 'Missing'}")
    validations.append(f"Network: {'Reachable' if network_ok else 'Unavailable'}")
    validations.append(f"Pacman Lock: {'Present' if pacman_lock else 'Clear'}")
    if free_gib is not None:
        validations.append(f"Free Disk Space: {free_gib:.1f} GiB")
    if header_status is not None:
        validations.append(f"Kernel Headers: {'Installed' if header_status else 'Missing'} ({header_detail})")

    # BUG #36: Warn when kernel-bundled NVIDIA conflicts with selected driver packages
    bundled_nvidia = _detect_kernel_bundled_nvidia()
    nvidia_driver_pkgs = {"nvidia-open-dkms", "nvidia-open", "nvidia-dkms", "nvidia"}
    user_wants_nvidia = any(pkg in nvidia_driver_pkgs for pkg in state.driver_packages)
    if bundled_nvidia:
        validations.append(f"Kernel NVIDIA Module: Bundled ({', '.join(bundled_nvidia)})")
        if user_wants_nvidia:
            warnings.append(
                f"Kernel-bundled NVIDIA detected ({', '.join(bundled_nvidia)}). "
                "Installing a separate nvidia-open-dkms or nvidia-dkms will conflict. "
                "Arctyx will automatically skip the kernel module package and install userspace tools only."
            )
    elif user_wants_nvidia:
        validations.append("Kernel NVIDIA Module: Not Bundled (standard install)")

    if state.bootloader_action in {"fix", "replace"}:
        validations.append(f"Bootloader Action: {state.bootloader_action.replace('-', ' ').title()}")
    else:
        validations.append("Bootloader Action: Keep Current")

    if state.bootloader_action in {"fix", "replace"}:
        if not is_uefi:
            warnings.append("Bootloader repair or replacement is most reliable on UEFI systems. Legacy BIOS paths are only partially automated.")
        if state.bootloader_action == "replace" and state.bootloader_choice in {"systemd-boot", "refind", "no-bootloader"} and not is_uefi:
            warnings.append(f"{state.bootloader_choice} requires UEFI firmware. This choice will not apply cleanly on Legacy BIOS.")
        if state.bootloader_action == "replace" and state.bootloader_choice in {"grub", "systemd-boot", "refind", "no-bootloader"} and not esp_mount:
            warnings.append("No EFI System Partition mount was detected. Mount the ESP before applying bootloader changes.")
        if state.bootloader_choice == "grub" and not boot_mounted:
            warnings.append("/boot is not mounted. GRUB config generation or reinstall may fail until /boot is mounted.")

    if state.boot_os_prober_action == "on" and not os_prober_available:
        warnings.append("OS-Prober is enabled but not currently installed. Arctyx will try to auto-install it during apply.")
    if pacman_lock:
        warnings.append("Pacman lock file is present. Another package operation may still be active.")
    if not network_ok:
        warnings.append("Network connectivity check failed. Package downloads or AUR validation may fail during apply.")
    if free_gib is not None and free_gib < 2:
        warnings.append("Free disk space is very low. Package installation and initramfs generation may fail.")
    if header_status is False:
        warnings.append(f"DKMS-style driver packages are selected, but {header_detail} is missing.")

    if state.autologin and state.login_method == "tty-autologin":
        warnings.append("TTY autologin allows local physical access without a password.")

    if not state.package_categories:
        warnings.append("No package group is selected. The install will stay very minimal unless apps or desktop packages add dependencies.")

    if not state.desktop_sessions and state.login_method == "display-manager":
        warnings.append("A display manager is selected without a desktop session. Login may succeed but no desktop session may be available.")

    if not state.desktop_sessions and state.autostart_enabled and state.autostart_session != "custom":
        warnings.append("Autostart is enabled without a selected desktop session. Consider selecting a desktop or switching autostart to a custom command.")

    if "gnome" in state.desktop_sessions and state.display_manager in {"none", "lightdm", "ly"}:
        recommendations.append("GNOME usually works best with GDM for a smoother Wayland login flow.")
    if "plasma" in state.desktop_sessions and state.display_manager in {"none", "gdm", "lightdm", "ly"}:
        recommendations.append("Plasma is usually cleanest with SDDM as the display manager.")
    if any(session in state.desktop_sessions for session in {"hyprland", "sway", "river", "niri"}) and state.login_method == "display-manager" and state.display_manager == "none":
        recommendations.append("For Wayland compositors, either choose a display manager explicitly or keep TTY Autologin for a lighter setup.")

    if state.bootloader_action == "replace" and state.bootloader_choice == "grub" and state.boot_os_prober_action == "off":
        recommendations.append("If you dual-boot with Windows or another OS, enabling OS-Prober with GRUB is usually the safer choice.")
    if state.bootloader_action == "keep" and state.boot_os_prober_action == "on" and not os_prober_available:
        recommendations.append("If you do not dual-boot, disabling OS-Prober avoids an unnecessary extra package and scan.")
    if pacman_lock:
        recommendations.append("If no package manager is actually running, remove the stale pacman lock before applying.")
    if header_status is False:
        recommendations.append(f"Install {header_detail} before apply so DKMS GPU or Wi-Fi modules can build successfully.")
    if free_gib is not None and free_gib < 5:
        recommendations.append("Consider freeing a bit more disk space before applying large desktop or driver changes.")

    if state.shell_choice == "oh-my-zsh" and state.aur_helper == "skip":
        recommendations.append("If you plan to add more desktop apps later, choosing Yay or Paru now can make AUR installs easier.")

    if state.driver_mode == "skip" and state.desktop_sessions:
        recommendations.append("If this system has dedicated graphics hardware, consider Auto Detect And Install under Drivers before applying.")

    if not state.desktop_sessions and not state.selected_apps and not state.selected_ides:
        recommendations.append("This plan is very lean right now. That is fine if you want a minimal base, but double-check that it matches your goal.")

    ready = not any(
        warning.startswith(prefix)
        for warning in warnings
        for prefix in (
            "systemd-boot requires",
            "No EFI System Partition",
            "Pacman lock file is present",
        )
    )
    if any("will not apply cleanly" in warning for warning in warnings):
        ready = False
    if any("DKMS-style driver packages are selected" in warning for warning in warnings):
        ready = False

    report = ReviewReport(ready=ready, validations=validations, warnings=warnings, recommendations=recommendations)
    _REVIEW_CACHE[signature] = (now, report)
    return report
