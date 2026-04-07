#!/usr/bin/env bash
set -euo pipefail

backend_login_apply() {
  local auth_pkg="$1"
  local auth_agent_cmd=""

  if [[ "$LOGIN_METHOD" == "display-manager" ]]; then
    log "Login mode: Display Manager (${DISPLAY_MANAGER_CHOICE:-none})"
    ensure_display_manager_selected
  elif [[ "$LOGIN_METHOD" == "tty-autologin" && "$AUTOLOGIN_ENABLE" == "yes" ]]; then
    log "Login mode: TTY Autologin on ${TTY_DEVICE:-tty1}"
    disable_display_managers_for_autologin
    configure_tty_autologin
  elif [[ "$LOGIN_METHOD" == "manual" ]]; then
    log "Login mode: Manual"
    apply_manual_login_mode
  fi

  if [[ "$LOGIN_METHOD" == "tty-autologin" && "${AUTOSTART_ACTION:-skip}" == "off" ]]; then
    log "Autostart action: Off (removing managed autostart block if present)"
    remove_autostart_block "$SHELL_RC_FILE"
  elif [[ "$LOGIN_METHOD" == "tty-autologin" && "$AUTOSTART_ENABLE" == "yes" && "${AUTOSTART_ACTION:-skip}" == "on" ]]; then
    install_missing_autostart_session_if_selected
    local cmd
    cmd="$(get_autostart_command)"
    if [[ -z "$cmd" ]]; then
      err "Autostart command is empty."
      exit 1
    fi
    auth_agent_cmd="$(resolve_auth_agent_start_cmd "$auth_pkg")"
    if [[ "$SESSION_CHOICE" == "custom" ]]; then
      log "Autostart action: On (custom command: $CUSTOM_AUTOSTART_CMD)"
    else
      log "Autostart action: On (session: $SESSION_CHOICE)"
    fi
    inject_autostart_block "$cmd" "$auth_agent_cmd"
  elif [[ "$LOGIN_METHOD" == "tty-autologin" && "${AUTOSTART_ACTION:-skip}" == "skip" ]]; then
    log "Autostart action: Skip (leaving current autostart state untouched)"
  fi
}
