#!/usr/bin/env bash
set -euo pipefail

backend_drivers_apply() {
  install_driver_configuration_if_selected
  post_install_bluetooth
  # BUG #40: bluez alone doesn't give you BT audio; pipewire-audio is required.
  # Only install if bluez was actually installed and PulseAudio isn't present.
  if pacman -Q bluez >/dev/null 2>&1; then
    if ! pacman -Q pulseaudio >/dev/null 2>&1; then
      pacman -S --needed --noconfirm pipewire-audio 2>/dev/null || true
    fi
  fi
}
