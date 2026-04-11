#!/usr/bin/env bash
set -euo pipefail

backend_desktop_apply() {
  install_selected_dewm_packages
  ensure_audio_if_desktop
}
