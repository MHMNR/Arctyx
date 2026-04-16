#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ROOT="$(cd "$BACKEND_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SETUP_ROOT/.." && pwd)"
LEGACY_SETUP_SH="$PROJECT_ROOT/setup.sh"

if [[ ! -f "$LEGACY_SETUP_SH" ]]; then
  echo "[backend:error] setup.sh not found at $LEGACY_SETUP_SH" >&2
  exit 1
fi

export SETUP_LIB_MODE=1
# shellcheck disable=SC1090
source "$LEGACY_SETUP_SH"

backend_require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "[backend:error] jq is required for the hybrid backend." >&2
    exit 1
  }
}

backend_json_bool_to_yesno() {
  [[ "$1" == "true" ]] && printf 'yes\n' || printf 'no\n'
}

backend_json_array_to_words() {
  local filter="$1"
  jq -r "$filter | join(\" \")" "$STATE_FILE"
}

backend_load_os_release() {
  if [[ -z "${BACKEND_OS_RELEASE_LOADED:-}" ]]; then
    if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      source /etc/os-release
      BACKEND_OS_ID="${ID:-linux}"
      BACKEND_OS_ID_LIKE="${ID_LIKE:-}"
      BACKEND_OS_NAME="${NAME:-${BACKEND_OS_ID}}"
      BACKEND_OS_PRETTY_NAME="${PRETTY_NAME:-${BACKEND_OS_NAME}}"
    else
      BACKEND_OS_ID="linux"
      BACKEND_OS_ID_LIKE=""
      BACKEND_OS_NAME="Linux"
      BACKEND_OS_PRETTY_NAME="Linux"
    fi
    BACKEND_OS_RELEASE_LOADED=1
  fi
}

backend_is_arch_family() {
  backend_load_os_release
  [[ "${BACKEND_OS_ID:-}" == "arch" ]] && return 0
  [[ " ${BACKEND_OS_ID_LIKE:-} " == *" arch "* ]] && return 0
  command -v pacman >/dev/null 2>&1 && [[ -f /etc/pacman.conf ]]
}

backend_system_firmware_label() {
  backend_load_os_release
  local label="${BACKEND_OS_NAME:-Linux}"
  label="${label%% GNU/Linux}"
  label="$(printf '%s' "$label" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  [[ -n "$label" ]] || label="Linux"
  printf '%s\n' "$label"
}

backend_system_entry_dir() {
  local label
  label="$(backend_system_firmware_label)"
  label="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  [[ -n "$label" ]] || label="linux"
  printf '%s\n' "$label"
}

backend_detect_kernel_assets() {
  local pkgbase kernel_path initramfs_path
  if [[ -r "/usr/lib/modules/$(uname -r)/pkgbase" ]]; then
    pkgbase="$(<"/usr/lib/modules/$(uname -r)/pkgbase")"
    kernel_path="/boot/vmlinuz-${pkgbase}"
    initramfs_path="/boot/initramfs-${pkgbase}.img"
    if [[ -f "$kernel_path" && -f "$initramfs_path" ]]; then
      printf '%s|%s\n' "$kernel_path" "$initramfs_path"
      return 0
    fi
  fi

  for kernel_path in /boot/vmlinuz-*; do
    [[ -f "$kernel_path" ]] || continue
    pkgbase="${kernel_path##*/vmlinuz-}"
    initramfs_path="/boot/initramfs-${pkgbase}.img"
    if [[ -f "$initramfs_path" ]]; then
      printf '%s|%s\n' "$kernel_path" "$initramfs_path"
      return 0
    fi
  done

  return 1
}

backend_load_state() {
  STATE_FILE="$1"
  [[ -f "$STATE_FILE" ]] || {
    echo "[backend:error] state file not found: $STATE_FILE" >&2
    exit 1
  }

  backend_require_jq

  MODE="$(jq -r '.workflow.mode // "install"' "$STATE_FILE")"
  START_SECTION="$(jq -r '.workflow.start_section // 1' "$STATE_FILE")"
  SECTION_CONTINUE="$(jq -r '.workflow.continue // false' "$STATE_FILE" | sed 's/true/yes/; s/false/no/')"
  MODE_FORCED="yes"

  TARGET_USER="$(jq -r '.user.target // empty' "$STATE_FILE")"
  [[ -n "$TARGET_USER" ]] || TARGET_USER="$DEFAULT_USER"
  refresh_user_context

  ARCH_BASE_ENABLE="$(backend_json_bool_to_yesno "$(jq -r '.packages.base_enable // false' "$STATE_FILE")")"
  ARCH_BASE_PRESET="base-cli"
  ARCH_OPTIMIZE_MIRRORS="$(backend_json_bool_to_yesno "$(jq -r '.packages.optimize_mirrors // false' "$STATE_FILE")")"
  ARCH_MIRROR_REGIONS="$(backend_json_array_to_words '.packages.mirror_regions // []')"
  ARCH_SELECTED_CATEGORIES="$(backend_json_array_to_words '.packages.categories // []')"
  ARCH_SELECTED_IDES="$(backend_json_array_to_words '.apps.ides // []')"
  ARCH_SELECTED_APPS="$(backend_json_array_to_words '.apps.selected // []')"
  ARCH_CUSTOM_APP_PKGS="$(backend_json_array_to_words '.apps.custom // []')"
  ARCH_SHELL_CHOICE="$(jq -r '.packages.shell_choice // "bash"' "$STATE_FILE")"
  ARCH_AUR_HELPER="$(jq -r '.packages.aur_helper // "skip"' "$STATE_FILE")"
  ARCH_ENABLE_MULTILIB="$(backend_json_bool_to_yesno "$(jq -r '.packages.multilib // false' "$STATE_FILE")")"
  ARCH_ENABLE_CORE_TESTING="$(backend_json_bool_to_yesno "$(jq -r '.packages.core_testing // false' "$STATE_FILE")")"
  ARCH_ENABLE_EXTRA_TESTING="$(backend_json_bool_to_yesno "$(jq -r '.packages.extra_testing // false' "$STATE_FILE")")"
  ARCH_ENABLE_MULTILIB_TESTING="$(backend_json_bool_to_yesno "$(jq -r '.packages.multilib_testing // false' "$STATE_FILE")")"
  ARCH_ENABLE_CHAOTIC_AUR="$(backend_json_bool_to_yesno "$(jq -r '.packages.chaotic_aur // false' "$STATE_FILE")")"

  DEWM_SELECTED="$(backend_json_array_to_words '.desktop.sessions // []')"
  DEWM_INSTALL_MODE="$(jq -r '.desktop.profile // "full"' "$STATE_FILE")"
  ARCH_SELECTED_DE="$(jq -r '.desktop.primary // "none"' "$STATE_FILE")"
  ARCH_CUSTOM_DE_PKGS="$(backend_json_array_to_words '.desktop.custom_packages // []')"

  LOGIN_METHOD="$(jq -r '.login.method // "tty-autologin"' "$STATE_FILE")"
  DISPLAY_MANAGER_CHOICE="$(jq -r '.login.display_manager // "none"' "$STATE_FILE")"
  AUTOLOGIN_ENABLE="$(backend_json_bool_to_yesno "$(jq -r '.login.autologin // false' "$STATE_FILE")")"
  AUTOLOGIN_DM_ACTION="$(jq -r '.login.dm_action // "keep"' "$STATE_FILE")"
  TTY_DEVICE="$(jq -r '.login.tty_device // "tty1"' "$STATE_FILE")"
  AUTOSTART_ACTION="$(jq -r '.login.autostart.action // empty' "$STATE_FILE")"
  AUTOSTART_ENABLE="$(backend_json_bool_to_yesno "$(jq -r '.login.autostart.enabled // false' "$STATE_FILE")")"
  if [[ -z "$AUTOSTART_ACTION" ]]; then
    [[ "$AUTOSTART_ENABLE" == "yes" ]] && AUTOSTART_ACTION="on" || AUTOSTART_ACTION="skip"
  fi
  SESSION_CHOICE="$(jq -r '.login.autostart.session // "hyprland"' "$STATE_FILE")"
  CUSTOM_AUTOSTART_CMD="$(jq -r '.login.autostart.command // ""' "$STATE_FILE")"
  AUTOSTART_INSTALL_MISSING_SESSION="$(backend_json_bool_to_yesno "$(jq -r '.login.autostart.install_missing // false' "$STATE_FILE")")"
  AUTOSTART_SESSION_INSTALL_PROFILE="$(jq -r '.login.autostart.install_profile // "core"' "$STATE_FILE")"

  DRIVER_CONFIG_MODE="$(jq -r '.drivers.mode // "skip"' "$STATE_FILE")"
  DRIVER_SELECTED_GROUPS="$(backend_json_array_to_words '.drivers.selected_groups // []')"
  DRIVER_SELECTED_PKGS_PACMAN="$(backend_json_array_to_words '.drivers.pacman_packages // []')"
  DRIVER_SELECTED_PKGS_AUR="$(backend_json_array_to_words '.drivers.aur_packages // []')"

  BOOT_TUNE_ENABLE="$(backend_json_bool_to_yesno "$(jq -r '.boot.enabled // true' "$STATE_FILE")")"
  BOOT_SPLASH_MODE="$(jq -r '.boot.splash_mode // "skip"' "$STATE_FILE")"
  BOOT_OS_PROBER_ACTION="$(jq -r '.boot.os_prober_action // "skip"' "$STATE_FILE")"
  BOOTLOADER_ACTION="$(jq -r '.boot.bootloader_action // empty' "$STATE_FILE")"
  if [[ -z "$BOOTLOADER_ACTION" ]]; then
    if [[ "$(jq -r '.boot.replace_bootloader // false' "$STATE_FILE")" == "true" ]]; then
      BOOTLOADER_ACTION="replace"
    else
      BOOTLOADER_ACTION="keep"
    fi
  fi
  BOOTLOADER_REPLACE="$(backend_json_bool_to_yesno "$(jq -r '.boot.replace_bootloader // false' "$STATE_FILE")")"
  BOOTLOADER_CHOICE="$(jq -r '.boot.bootloader // "grub"' "$STATE_FILE")"

  SAVE_PROFILE="$(backend_json_bool_to_yesno "$(jq -r '.profile.save // false' "$STATE_FILE")")"
  PROFILE_NAME="$(jq -r '.profile.name // empty' "$STATE_FILE")"

  FILE_MANAGER_CHOICE="skip"
  FILE_MANAGER_MODE="full"
  AUTH_AGENT_CHOICE="auto"

  detect_environment
  tui_normalize_state
}

backend_state_action() {
  jq -r '.workflow.action // "apply"' "$STATE_FILE"
}

backend_print_state_summary() {
  printf '[backend] state=%s action=%s user=%s\n' "$STATE_FILE" "$(backend_state_action)" "$TARGET_USER"
}
