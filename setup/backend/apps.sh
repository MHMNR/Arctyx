#!/usr/bin/env bash
set -euo pipefail

backend_apps_prepare() {
  :
}

backend_apps_summary() {
  printf 'apps=%s ides=%s custom=%s\n' \
    "${ARCH_SELECTED_APPS:-none}" \
    "${ARCH_SELECTED_IDES:-none}" \
    "${ARCH_CUSTOM_APP_PKGS:-none}"
}
