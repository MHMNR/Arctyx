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
  if backend_packages_need_pacman_db; then
    ensure_pacman_db_ready
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
