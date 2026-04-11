#!/usr/bin/env bash
set -euo pipefail

backend_select_backup_dir() {
  mkdir -p "$BACKUP_ROOT"
  local backups=()
  local b sorted_backups=""
  for b in "$BACKUP_ROOT"/*; do
    [[ -e "$b" ]] || continue
    backups+=("$b")
  done
  if (( ${#backups[@]} > 1 )); then
    sorted_backups="$(printf '%s\n' "${backups[@]}" | sort -r)"
    backups=()
    while IFS= read -r b; do
      [[ -n "$b" ]] || continue
      backups+=("$b")
    done <<< "$sorted_backups"
  fi

  if (( ${#backups[@]} == 0 )); then
    err "No backups found in $BACKUP_ROOT"
    exit 1
  fi

  local options=() base selected
  for b in "${backups[@]}"; do
    base="$(basename "$b")"
    options+=("${base}|Rollback snapshot")
  done
  selected="$(choose_menu 'Available Backups' "${options[@]}")"
  selected="$(echo "$selected" | xargs)"
  [[ -n "$selected" ]] || { err "Backup selection cancelled."; exit 1; }

  for b in "${backups[@]}"; do
    if [[ "$(basename "$b")" == "$selected" ]]; then
      printf '%s\n' "$b"
      return 0
    fi
  done

  err "Selected backup not found: $selected"
  exit 1
}

backend_rollback_from_backup() {
  local bdir
  bdir="$(backend_select_backup_dir)"

  if [[ ! -f "$bdir/state-before.tar" ]]; then
    err "state-before.tar missing in $bdir"
    exit 1
  fi

  local bad=0 entry tar_entries=""
  tar_entries="$(tar -tf "$bdir/state-before.tar" 2>/dev/null || true)"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" == /* || "$entry" == *"/../"* || "$entry" == "../"* || "$entry" == *"/.." || "$entry" == *$'\0'* ]]; then
      bad=1
      break
    fi
  done <<< "$tar_entries"
  if [[ "$bad" -ne 0 ]]; then
    err "Refusing rollback: backup archive contains unsafe paths."
    exit 1
  fi

  warn "Rollback restores the saved managed configuration files only."
  warn "It does not roll back installed packages, package databases, or broader system state."
  log "Restoring from $bdir/state-before.tar"
  tar -xpf "$bdir/state-before.tar" -C /
  systemctl daemon-reload || true
  log "Rollback complete."
}

backend_uninstall_managed_config() {
  TTY_DEVICE="$(ask_input_default 'TTY to clean (autologin drop-in)' 'tty1')"

  local dropin="/etc/systemd/system/getty@${TTY_DEVICE}.service.d/autologin.conf"
  if [[ -f "$dropin" ]]; then
    rm -f "$dropin"
    rmdir --ignore-fail-on-non-empty "/etc/systemd/system/getty@${TTY_DEVICE}.service.d" || true
    systemctl daemon-reload || true
    log "Removed $dropin"
  else
    warn "No autologin drop-in found at $dropin"
  fi

  remove_autostart_block "$SHELL_RC_FILE"
  chown "$TARGET_USER:$TARGET_USER" "$SHELL_RC_FILE" 2>/dev/null || true
  log "Removed managed autostart block from $SHELL_RC_FILE"

  if ask_yes_no 'Disable linger for this user?' 'n'; then
    loginctl disable-linger "$TARGET_USER" || true
  fi

  warn 'Uninstall mode removes managed config only. It does not uninstall packages.'
}

backend_save_profile() {
  [[ "$SAVE_PROFILE" == "yes" ]] || return 0
  mkdir -p "$PROFILE_ROOT"
  local name pf
  name="${PROFILE_NAME:-${TARGET_USER}-${TS}}"
  pf="$PROFILE_ROOT/${name}.env"

  cat > "$pf" <<EOP
TARGET_USER=$TARGET_USER
TTY_DEVICE=$TTY_DEVICE
ARCH_BASE_ENABLE="$ARCH_BASE_ENABLE"
ARCH_BASE_PRESET="$ARCH_BASE_PRESET"
ARCH_AUR_HELPER="$ARCH_AUR_HELPER"
ARCH_ENABLE_MULTILIB="$ARCH_ENABLE_MULTILIB"
ARCH_ENABLE_CORE_TESTING="$ARCH_ENABLE_CORE_TESTING"
ARCH_ENABLE_EXTRA_TESTING="$ARCH_ENABLE_EXTRA_TESTING"
ARCH_ENABLE_MULTILIB_TESTING="$ARCH_ENABLE_MULTILIB_TESTING"
ARCH_ENABLE_CHAOTIC_AUR="$ARCH_ENABLE_CHAOTIC_AUR"
ARCH_SELECTED_CATEGORIES="$ARCH_SELECTED_CATEGORIES"
ARCH_SELECTED_IDES="$ARCH_SELECTED_IDES"
ARCH_SELECTED_APPS="$ARCH_SELECTED_APPS"
ARCH_CUSTOM_APP_PKGS="$ARCH_CUSTOM_APP_PKGS"
ARCH_SELECTED_DE="$ARCH_SELECTED_DE"
ARCH_CUSTOM_DE_PKGS="$ARCH_CUSTOM_DE_PKGS"
DEWM_SELECTED="$DEWM_SELECTED"
DEWM_INSTALL_MODE="$DEWM_INSTALL_MODE"
ARCH_INSTALL_FISH="$ARCH_INSTALL_FISH"
ARCH_INSTALL_ZSH="$ARCH_INSTALL_ZSH"
ARCH_INSTALL_OH_MY_ZSH="$ARCH_INSTALL_OH_MY_ZSH"
ARCH_SHELL_CHOICE="$ARCH_SHELL_CHOICE"
ARCH_OPTIMIZE_MIRRORS="$ARCH_OPTIMIZE_MIRRORS"
FILE_MANAGER_CHOICE=$FILE_MANAGER_CHOICE
FILE_MANAGER_MODE=$FILE_MANAGER_MODE
AUTH_AGENT_CHOICE=$AUTH_AGENT_CHOICE
AUTOLOGIN_ENABLE=$AUTOLOGIN_ENABLE
AUTOLOGIN_DM_ACTION=$AUTOLOGIN_DM_ACTION
LOGIN_METHOD=$LOGIN_METHOD
DISPLAY_MANAGER_CHOICE=$DISPLAY_MANAGER_CHOICE
AUTOSTART_ACTION=$AUTOSTART_ACTION
AUTOSTART_ENABLE=$AUTOSTART_ENABLE
SESSION_CHOICE=$SESSION_CHOICE
CUSTOM_AUTOSTART_CMD="$CUSTOM_AUTOSTART_CMD"
AUTOSTART_INSTALL_MISSING_SESSION=$AUTOSTART_INSTALL_MISSING_SESSION
AUTOSTART_SESSION_INSTALL_PROFILE=$AUTOSTART_SESSION_INSTALL_PROFILE
BOOT_TUNE_ENABLE=$BOOT_TUNE_ENABLE
BOOT_SPLASH_MODE=$BOOT_SPLASH_MODE
BOOT_OS_PROBER_ACTION=$BOOT_OS_PROBER_ACTION
BOOTLOADER_ACTION=$BOOTLOADER_ACTION
BOOTLOADER_REPLACE=$BOOTLOADER_REPLACE
BOOTLOADER_CHOICE=$BOOTLOADER_CHOICE
DRIVER_CONFIG_MODE=$DRIVER_CONFIG_MODE
DRIVER_SELECTED_GROUPS="$DRIVER_SELECTED_GROUPS"
DRIVER_SELECTED_PKGS_PACMAN="$DRIVER_SELECTED_PKGS_PACMAN"
DRIVER_SELECTED_PKGS_AUR="$DRIVER_SELECTED_PKGS_AUR"
EOP

  log "Profile saved: $pf"
}

backend_user_prepare() {
  refresh_user_context
}

backend_user_backup() {
  create_backup_snapshot
}

backend_user_save_profile() {
  backend_save_profile
}

backend_user_uninstall() {
  backend_uninstall_managed_config
}

backend_user_rollback() {
  backend_rollback_from_backup
}
