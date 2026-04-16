#!/usr/bin/env bash
set -euo pipefail

backend_packages_need_pacman_db() {
  if [[ "$ARCH_BASE_ENABLE" == "yes" || -n "${DEWM_SELECTED:-}" || -n "${DRIVER_SELECTED_PKGS_PACMAN:-}" ]]; then
    return 0
  fi
  if [[ "$LOGIN_METHOD" == "display-manager" ]]; then
    return 0
  fi
  if [[ "$LOGIN_METHOD" == "tty-autologin" && "$AUTOSTART_ENABLE" == "yes" && "$AUTOSTART_INSTALL_MISSING_SESSION" == "yes" && "$SESSION_CHOICE" != "custom" ]]; then
    return 0
  fi
  return 1
}

backend_packages_prepare() {
  # 1. Ensure databases are ready BEFORE we run the unified probe
  ensure_pacman_db_ready
  
  # 2. Force a unified resolution of all intended packages
  if command -v resolve_arch_plan >/dev/null 2>&1; then
    log "Building unified installation plan and probing for conflicts..."
    resolve_arch_plan >/dev/null 2>&1 || true
    
    # 3. Run the dynamic conflict resolver on the aggregate list
    if [[ ${#ARCH_TOTAL_PACMAN_PKGS[@]} -gt 0 ]]; then
      resolve_all_conflicts_dynamically "${ARCH_TOTAL_PACMAN_PKGS[@]}"
    fi
  fi
}

backend_packages_apply() {

  install_arch_base_if_selected
  install_oh_my_zsh_if_selected
  set_default_shell_if_selected
  post_install_networkmanager
  post_install_docker
  post_install_bluetooth
  post_install_virt_manager
  post_install_virtualbox
  post_install_rustup_default_toolchain
  post_install_storage_maintenance
  post_install_xdg_user_dirs
  post_install_firewall
}
