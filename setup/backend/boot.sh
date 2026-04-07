#!/usr/bin/env bash
set -euo pipefail

backend_is_uefi() {
  [[ -d /sys/firmware/efi ]]
}

backend_detect_esp_dir() {
  local candidate
  for candidate in /boot/efi /efi /boot; do
    [[ -d "$candidate" ]] || continue
    if findmnt -rn "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

backend_ensure_pkg() {
  pacman -S --needed --noconfirm "$@" || warn "Failed to install package(s): $*"
}

backend_detect_current_bootloader() {
  local esp_dir efiboot_output entry_dir label
  esp_dir="$(backend_detect_esp_dir || true)"
  efiboot_output="$(efibootmgr -v 2>/dev/null || true)"
  entry_dir="$(backend_system_entry_dir)"
  label="$(backend_system_firmware_label)"

  if command -v bootctl >/dev/null 2>&1 && bootctl is-installed >/dev/null 2>&1; then
    printf 'systemd-boot\n'
    return 0
  fi

  if [[ -n "$esp_dir" ]]; then
    [[ -d "$esp_dir/EFI/refind" || -d "$esp_dir/EFI/BOOT/refind" ]] && { printf 'refind\n'; return 0; }
    [[ -d "$esp_dir/EFI/GRUB" || -d "$esp_dir/EFI/grub" || -d /boot/grub ]] && { printf 'grub\n'; return 0; }
    [[ -f "$esp_dir/EFI/${entry_dir}/vmlinuz" || -f "$esp_dir/EFI/${entry_dir}/vmlinuz-linux" ]] && { printf 'no-bootloader\n'; return 0; }
  fi

  [[ -f /boot/limine.conf || -d /boot/limine ]] && { printf 'limine\n'; return 0; }
  grep -qi 'refind' <<<"$efiboot_output" && { printf 'refind\n'; return 0; }
  grep -qi 'grub' <<<"$efiboot_output" && { printf 'grub\n'; return 0; }
  grep -qi 'systemd' <<<"$efiboot_output" && { printf 'systemd-boot\n'; return 0; }
  grep -qi "${label} (Direct)" <<<"$efiboot_output" && { printf 'no-bootloader\n'; return 0; }

  return 1
}

backend_relabel_efi_entry_by_match() {
  local match="$1" new_label="$2" efiboot_output bootnum line
  efiboot_output="$(efibootmgr -v 2>/dev/null || true)"
  while IFS= read -r line; do
    grep -qi "$match" <<<"$line" || continue
    bootnum="$(sed -n 's/^Boot\([0-9A-Fa-f]\+\)\*.*/\1/p' <<<"$line")"
    [[ -n "$bootnum" ]] || continue
    efibootmgr -b "$bootnum" -L "$new_label" >/dev/null 2>&1 || true
    return 0
  done <<<"$efiboot_output"
  return 1
}

backend_grub_install() {
  local esp_dir bootloader_id boot_label
  backend_ensure_pkg grub efibootmgr
  bootloader_id="$(backend_system_entry_dir)"
  boot_label="$(backend_system_firmware_label)"
  if backend_is_uefi; then
    esp_dir="$(backend_detect_esp_dir || true)"
    if [[ -z "$esp_dir" ]]; then
      warn "UEFI system detected, but no EFI system partition mount point was found."
      return 1
    fi
    grub-install --target=x86_64-efi --efi-directory="$esp_dir" --bootloader-id="$bootloader_id" --recheck || {
      warn "GRUB installation failed."
      return 1
    }
    backend_relabel_efi_entry_by_match "$bootloader_id" "$boot_label" || true
  else
    warn "Non-UEFI GRUB replacement is not automated in this backend yet."
    return 1
  fi
  regenerate_bootloader_config || true
}

backend_systemd_boot_install() {
  local esp_dir boot_label
  backend_ensure_pkg efibootmgr
  boot_label="$(backend_system_firmware_label)"
  if ! backend_is_uefi; then
    warn "systemd-boot requires UEFI firmware."
    return 1
  fi
  esp_dir="$(backend_detect_esp_dir || true)"
  if [[ -z "$esp_dir" ]]; then
    warn "Unable to detect the EFI system partition mount point for systemd-boot."
    return 1
  fi
  bootctl --path="$esp_dir" --efi-boot-option-description="$boot_label" install || {
    warn "systemd-boot installation failed."
    return 1
  }
}

backend_refind_install() {
  local boot_label
  backend_ensure_pkg refind efibootmgr
  boot_label="$(backend_system_firmware_label)"
  if ! backend_is_uefi; then
    warn "rEFInd requires UEFI firmware."
    return 1
  fi
  if ! command -v refind-install >/dev/null 2>&1; then
    warn "refind-install was not found after installing rEFInd."
    return 1
  fi
  refind-install || {
    warn "rEFInd installation failed."
    return 1
  }
  backend_relabel_efi_entry_by_match 'refind' "$boot_label" || true
}

backend_limine_install() {
  local boot_label
  backend_ensure_pkg limine
  boot_label="$(backend_system_firmware_label)"
  backend_relabel_efi_entry_by_match 'limine' "$boot_label" || true
  warn "Limine package installed. Full automated Limine deployment is not implemented yet; manual finalization may still be required."
}

backend_direct_uefi_entry_install() {
  local esp_dir esp_source disk part root_source root_uuid entry_dir loader_path unicode_args kernel_path initramfs_path label kernel_assets
  backend_ensure_pkg efibootmgr
  if ! backend_is_uefi; then
    warn "Direct UEFI boot entry setup requires UEFI firmware."
    return 1
  fi
  esp_dir="$(backend_detect_esp_dir || true)"
  if [[ -z "$esp_dir" ]]; then
    warn "Unable to detect the EFI system partition mount point for direct UEFI entry setup."
    return 1
  fi
  esp_source="$(findmnt -rn -o SOURCE "$esp_dir" || true)"
  if [[ -z "$esp_source" ]]; then
    warn "Unable to detect the backing device for $esp_dir."
    return 1
  fi
  disk="/dev/$(lsblk -no PKNAME "$esp_source" 2>/dev/null || true)"
  part="$(lsblk -no PARTNUM "$esp_source" 2>/dev/null || true)"
  if [[ -z "$disk" || -z "$part" ]]; then
    warn "Unable to determine disk/partition information for EFI entry creation."
    return 1
  fi

  kernel_assets="$(backend_detect_kernel_assets || true)"
  kernel_path="${kernel_assets%%|*}"
  initramfs_path="${kernel_assets#*|}"
  [[ -n "$kernel_assets" && -f "$kernel_path" && -f "$initramfs_path" ]] || {
    warn "Kernel or initramfs image not found for direct UEFI boot entry setup."
    return 1
  }

  entry_dir="$esp_dir/EFI/$(backend_system_entry_dir)"
  label="$(backend_system_firmware_label)"
  mkdir -p "$entry_dir"
  cp -f "$kernel_path" "$entry_dir/vmlinuz"
  cp -f "$initramfs_path" "$entry_dir/initramfs.img"

  unicode_args=""
  root_source="$(findmnt -rn -o SOURCE / || true)"
  root_uuid="$(blkid -s UUID -o value "$root_source" 2>/dev/null || true)"
  if [[ -n "$root_uuid" ]]; then
    unicode_args="root=UUID=$root_uuid rw"
  else
    unicode_args="rw"
  fi

  if [[ -f /boot/intel-ucode.img ]]; then
    cp -f /boot/intel-ucode.img "$entry_dir/intel-ucode.img"
    unicode_args="$unicode_args initrd=\\EFI\\$(backend_system_entry_dir | sed 's/\//\\/g')\\intel-ucode.img"
  elif [[ -f /boot/amd-ucode.img ]]; then
    cp -f /boot/amd-ucode.img "$entry_dir/amd-ucode.img"
    unicode_args="$unicode_args initrd=\\EFI\\$(backend_system_entry_dir | sed 's/\//\\/g')\\amd-ucode.img"
  fi
  unicode_args="$unicode_args initrd=\\EFI\\$(backend_system_entry_dir | sed 's/\//\\/g')\\initramfs.img"

  loader_path="\\EFI\\$(backend_system_entry_dir | sed 's/\//\\/g')\\vmlinuz"
  efibootmgr --create --disk "$disk" --part "$part" --label "${label} (Direct)" --loader "$loader_path" --unicode "$unicode_args" || {
    warn "Failed to create the direct UEFI boot entry."
    return 1
  }
}

backend_bootloader_apply() {
  local action choice
  action="${BOOTLOADER_ACTION:-}"
  if [[ -z "$action" ]]; then
    [[ "${BOOTLOADER_REPLACE:-no}" == "yes" ]] && action="replace" || action="keep"
  fi

  case "$action" in
    keep) return 0 ;;
    fix)
      choice="$(backend_detect_current_bootloader || true)"
      if [[ -z "$choice" ]]; then
        warn "Could not detect the current bootloader cleanly. Falling back to the selected replacement choice: ${BOOTLOADER_CHOICE:-grub}"
        choice="${BOOTLOADER_CHOICE:-grub}"
      fi
      ;;
    replace)
      choice="${BOOTLOADER_CHOICE:-grub}"
      ;;
    *)
      warn "Unsupported bootloader action: $action"
      return 1
      ;;
  esac

  case "$choice" in
    grub) backend_grub_install ;;
    systemd-boot) backend_systemd_boot_install ;;
    refind) backend_refind_install ;;
    limine) backend_limine_install ;;
    no-bootloader) backend_direct_uefi_entry_install ;;
    *)
      warn "Unsupported bootloader choice: ${choice:-unknown}"
      ;;
  esac
}

backend_boot_apply() {
  backend_bootloader_apply
  configure_gpu_boot_support
  if [[ "$BOOT_TUNE_ENABLE" == "yes" ]]; then
    configure_boot_tuning
  fi
}
