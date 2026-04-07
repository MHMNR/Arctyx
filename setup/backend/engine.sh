#!/usr/bin/env bash
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ENGINE_DIR/utils.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/user.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/apps.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/packages.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/desktop.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/login.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/drivers.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/boot.sh"
# shellcheck disable=SC1091
source "$ENGINE_DIR/preflight.sh"

backend_apply() {
  local auth_pkg
  backend_user_prepare
  precheck_distro
  backend_preflight_validate
  backend_user_backup
  backend_packages_prepare
  backend_apps_prepare
  backend_preflight_autofix

  auth_pkg="$(resolve_auth_agent_pkg)"

  backend_packages_apply
  backend_desktop_apply
  backend_login_apply "$auth_pkg"
  backend_drivers_apply
  backend_boot_apply

  post_checks
  backend_user_save_profile
}

main() {
  local state_file="${1:-}"
  local action

  if [[ -z "$state_file" ]]; then
    echo "Usage: $0 <state.json> [apply|plan|rollback|uninstall]" >&2
    exit 1
  fi

  backend_load_state "$state_file"
  action="${2:-$(backend_state_action)}"
  backend_print_state_summary

  case "$action" in
    apply)
      backend_apply
      ;;
    plan)
      print_plan
      ;;
    rollback)
      backend_user_rollback
      ;;
    uninstall)
      backend_user_uninstall
      ;;
    *)
      echo "[backend:error] unsupported action: $action" >&2
      exit 1
      ;;
  esac
}

main "$@"
