#!/usr/bin/env bash
set -euo pipefail

backend_has_network() {
  ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 \
    || ping -c 1 -W 1 github.com >/dev/null 2>&1 \
    || ping -c 1 -W 1 archlinux.org >/dev/null 2>&1
}

backend_pacman_lock_present() {
  [[ -e /var/lib/pacman/db.lck ]]
}

backend_detect_required_header_pkg() {
  case "$(uname -r 2>/dev/null || true)" in
    *-zen*) printf 'linux-zen-headers\n' ;;
    *-lts*) printf 'linux-lts-headers\n' ;;
    *-hardened*) printf 'linux-hardened-headers\n' ;;
    *) printf 'linux-headers\n' ;;
  esac
}

backend_autofix_dkms_headers() {
  driver_requires_dkms_headers || return 0
  local header_pkg
  header_pkg="$(backend_detect_required_header_pkg)"
  pacman -Q "$header_pkg" >/dev/null 2>&1 && return 0
  warn "Auto-heal: installing missing kernel header package for DKMS modules: $header_pkg"
  pacman -S --needed --noconfirm dkms "$header_pkg" || warn "Auto-heal: failed to install $header_pkg and dkms."
}

backend_preflight_validate() {
  if backend_pacman_lock_present; then
    err "Pacman lock file is present at /var/lib/pacman/db.lck. Clear the lock or wait for the current pacman process to finish."
    return 1
  fi

  if [[ "${BOOTLOADER_ACTION:-keep}" == "replace" || "${BOOTLOADER_ACTION:-keep}" == "fix" ]]; then
    if [[ "${BOOTLOADER_CHOICE:-}" == "grub" || "${BOOTLOADER_ACTION:-keep}" == "fix" ]]; then
      if [[ ! -d /boot ]]; then
        err "/boot is missing. Bootloader repair/replacement needs a mounted boot path."
        return 1
      fi
    fi
  fi

  if ! backend_has_network; then
    warn "Preflight: network connectivity check failed. Package downloads may fail during apply."
  fi

  # Dynamic Conflict Probing Engine
  if command -v resolve_arch_plan >/dev/null 2>&1; then
    # Building the plan to get the full list of missing packages
    resolve_arch_plan >/dev/null 2>&1 || true
    
    local -a pkgs_to_check=()
    # shellcheck disable=SC2206
    [[ -n "$ARCH_PACMAN_PKGS_RESOLVED" ]] && pkgs_to_check=($ARCH_PACMAN_PKGS_RESOLVED)
    
    if [[ ${#pkgs_to_check[@]} -gt 0 ]]; then
      local stderr
      stderr=$(pacman -Sw --noconfirm --needed "${pkgs_to_check[@]}" 2>&1 > /dev/null || true)
      
      if [[ -n "$stderr" && "$stderr" == *"conflict"* ]]; then
        local conflicts
        conflicts=$(echo "$stderr" | grep "are in conflict" | sed 's/:: //g' | tr '\n' ' ' | sed 's/  */ /g')
        
        warn "Preflight: Package conflicts detected: $conflicts. Automatic resolution will be attempted during installation."
      fi
    fi
  else
    warn "Preflight: resolve_arch_plan unavailable. Falling back to basic validation."
  fi
}

backend_preflight_autofix() {
  backend_autofix_dkms_headers

  if [[ "${BOOT_OS_PROBER:-no}" == "yes" ]]; then
    if command -v ensure_os_prober_ready >/dev/null 2>&1; then
      ensure_os_prober_ready || warn "Auto-heal: os-prober could not be prepared automatically. Continuing with warnings."
    else
      warn "Auto-heal: ensure_os_prober_ready is unavailable in this backend context."
    fi
  fi

  if [[ "${BOOTLOADER_ACTION:-keep}" == "fix" ]]; then
    if command -v backend_detect_current_bootloader >/dev/null 2>&1; then
      local detected_bootloader
      detected_bootloader="$(backend_detect_current_bootloader || true)"
      if [[ -n "$detected_bootloader" ]]; then
        BOOTLOADER_CHOICE="$detected_bootloader"
        printf '[backend:auto-heal] detected current bootloader: %s\n' "$BOOTLOADER_CHOICE"
      else
        warn "Auto-heal: could not detect the current bootloader. Apply will fall back to the saved bootloader choice if needed."
      fi
    fi
  fi

  if [[ "${BOOTLOADER_ACTION:-keep}" == "replace" && "${BOOTLOADER_CHOICE:-}" == "grub" ]]; then
    mkdir -p /boot/grub 2>/dev/null || true
  fi

  if [[ "${BOOTLOADER_ACTION:-keep}" == "replace" || "${BOOTLOADER_ACTION:-keep}" == "fix" ]]; then
    command -v efibootmgr >/dev/null 2>&1 || pacman -S --needed --noconfirm efibootmgr >/dev/null 2>&1 || true
  fi
}
