#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: setup.sh
  Launches the Arctyx modular wizard.

For non-interactive backend actions, use:
  python setup/main.py --action plan
  python setup/main.py --action apply
  python setup/main.py --action rollback
  python setup/main.py --action uninstall
EOF
  exit 0
fi

# Interactive system setup:
# - Base CLI + development package setup
# - Category-based app selection
# - TTY autologin
# - Shell-aware autostart on login
# - Optional boot tuning (GRUB/mkinitcpio)
# - Backup / rollback / uninstall helpers

if [[ "${SETUP_LIB_MODE:-0}" != "1" && ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_NAME="setup"
BACKUP_ROOT="/var/backups/${SCRIPT_NAME}"
PROFILE_ROOT="/etc/${SCRIPT_NAME}/profiles"
TS="$(date +%Y%m%d-%H%M%S)"

DEFAULT_USER="${SUDO_USER:-${USER:-$(logname 2>/dev/null || echo root)}}"
if command -v getent >/dev/null 2>&1 && ! getent passwd "$DEFAULT_USER" >/dev/null 2>&1; then
  DEFAULT_USER="root"
fi
MODE="install"
START_SECTION=1
MODE_FORCED="no"
SECTION_CONTINUE="no"

TARGET_USER=""
TARGET_HOME=""
TARGET_SHELL=""
SHELL_RC_FILE=""
TTY_DEVICE="tty1"

ARCH_BASE_ENABLE="no"
ARCH_BASE_PRESET="base-cli"
ARCH_AUR_HELPER="skip"
ARCH_ENABLE_MULTILIB="no"
ARCH_ENABLE_CORE_TESTING="no"
ARCH_ENABLE_EXTRA_TESTING="no"
ARCH_ENABLE_MULTILIB_TESTING="no"
ARCH_ENABLE_CHAOTIC_AUR="no"
ARCH_SELECTED_CATEGORIES=""
ARCH_SELECTED_IDES=""
ARCH_SELECTED_APPS=""
ARCH_CUSTOM_APP_PKGS=""
ARCH_SELECTED_DE="none"
ARCH_CUSTOM_DE_PKGS=""
ARCH_INSTALL_FISH="no"
ARCH_INSTALL_ZSH="no"
ARCH_INSTALL_OH_MY_ZSH="no"
ARCH_SHELL_CHOICE="bash"
ARCH_OPTIMIZE_MIRRORS="no"
ARCH_PACMAN_PKGS_RESOLVED=""
ARCH_PACMAN_PKGS_MISSING=""
ARCH_AUR_PKGS_RESOLVED=""
ARCH_AUR_PKGS_MISSING=""
ARCH_CUSTOM_APP_PKGS_INVALID=""
ARCH_CUSTOM_APP_PKGS_SKIPPED=""
ARCH_CUSTOM_APP_PKGS_VALID_PACMAN=""
ARCH_CUSTOM_APP_PKGS_VALID_AUR=""
AUR_RPC_VALIDATION_UNAVAILABLE="no"

FILE_MANAGER_CHOICE="skip"
FILE_MANAGER_MODE="full"
AUTH_AGENT_CHOICE="auto"

AUTOLOGIN_ENABLE="no"
AUTOLOGIN_DM_ACTION="disable"
LOGIN_METHOD="tty-autologin"
DISPLAY_MANAGER_CHOICE="none"
AUTOSTART_ACTION="skip"
AUTOSTART_ENABLE="no"
SESSION_CHOICE="hyprland"
CUSTOM_AUTOSTART_CMD=""
AUTOSTART_INSTALL_MISSING_SESSION="no"
AUTOSTART_SESSION_INSTALL_PROFILE="core"
DEWM_SELECTED=""
DEWM_INSTALL_MODE="full"

BOOT_TUNE_ENABLE="no"
BOOT_SILENT="yes"
BOOT_OS_PROBER="yes"
BOOT_PLYMOUTH_ACTION="skip"
BOOTLOADER_ACTION="keep"
BOOTLOADER_REPLACE="no"
BOOTLOADER_CHOICE="grub"

DRIVER_CONFIG_MODE="skip"
DRIVER_SELECTED_GROUPS=""
DRIVER_SELECTED_PKGS_PACMAN=""
DRIVER_SELECTED_PKGS_AUR=""
DRIVER_GPU_DETECTED_TEXT=""
DRIVER_CHIPSET_DETECTED_TEXT=""
DRIVER_NETWORK_DETECTED_TEXT=""
DRIVER_OTHERS_DETECTED_TEXT=""
DRIVER_GPU_RECO_PKGS=""
DRIVER_CHIPSET_RECO_PKGS=""
DRIVER_NETWORK_RECO_PKGS=""
DRIVER_OTHERS_RECO_PKGS=""
DRIVER_GPU_MENU_PKGS=""
DRIVER_CHIPSET_MENU_PKGS=""
DRIVER_NETWORK_MENU_PKGS=""
DRIVER_OTHERS_MENU_PKGS=""

PROFILE_NAME=""
SAVE_PROFILE="no"

MARK_START="# >>> tty_autostart_managed >>>"
MARK_END="# <<< tty_autostart_managed <<<"
UI_STACK_DEPTH=0
declare -Ag MENU_CURSOR_MEMORY=()
MENU_KEY_PUSHBACK=""
STARTUP_MENU_SELECTION=""

DETECTED_HYPRLAND="no"
DETECTED_PLASMA="no"
DETECTED_GNOME="no"
DETECTED_XFCE="no"
DETECTED_DM="none"

if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_TEXT="$(tput setaf 7)"
  C_SUBTEXT0="$(tput dim)"
  C_OVERLAY0="$(tput setaf 8 2>/dev/null || tput setaf 7)"
  C_OVERLAY1="$(tput setaf 6)"
  C_SURFACE0="$(tput setaf 8 2>/dev/null || tput setaf 0)"
  C_SURFACE1="$(tput setaf 8 2>/dev/null || tput setaf 0)"
  C_BLUE="$(tput setaf 4)"
  C_SAPPHIRE="$(tput setaf 6)"
  C_SKY="$(tput setaf 6)"
  C_TEAL="$(tput setaf 2)"
  C_LAVENDER="$(tput setaf 5)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_ROSEWATER="$(tput setaf 7)"
  C_FLAMINGO="$(tput setaf 1)"
  C_PINK="$(tput setaf 5)"
  C_RED="$(tput setaf 1)"
  C_MAUVE="$(tput setaf 5)"
  C_PEACH="$(tput setaf 3)"
else
  C_RESET=""; C_BOLD=""; C_TEXT=""; C_SUBTEXT0=""; C_OVERLAY0=""
  C_OVERLAY1=""; C_SURFACE0=""; C_SURFACE1=""; C_BLUE=""; C_SAPPHIRE=""
  C_SKY=""; C_TEAL=""; C_LAVENDER=""; C_GREEN=""; C_YELLOW=""
  C_ROSEWATER=""; C_FLAMINGO=""; C_PINK=""; C_RED=""; C_MAUVE=""
  C_PEACH=""
fi

log() { printf '%b[info]%b %s\n' "$C_SAPPHIRE" "$C_RESET" "$*"; }
warn() { printf '%b[warn]%b %s\n' "$C_PEACH" "$C_RESET" "$*"; }
err() { printf '%b[error]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
ui_invalid_selection() { printf '%bInvalid selection.%b\n' "$C_RED" "$C_RESET"; }

prompt_label() {
  printf '%b%s%b' "$C_ROSEWATER" "$1" "$C_RESET"
}

read_prompt() {
  local __var_name="$1"
  local __prompt="${2:-}"
  local __value=""
  if [[ -t 0 ]]; then
    if IFS= read -e -r -p "$__prompt" __value; then
      :
    elif IFS= read -r __value; then
      # Fallback for terminals/readline edge-cases so set -e doesn't terminate the app.
      :
    else
      printf -v "$__var_name" ''
      return 1
    fi
  else
    if IFS= read -r __value; then
      :
    else
      printf -v "$__var_name" ''
      return 1
    fi
  fi
  __value="${__value//$'\r'/}"
  printf -v "$__var_name" '%s' "$__value"
  return 0
}

get_cursor_row() {
  [[ -t 0 && -t 2 ]] || { printf '1\n'; return 0; }
  [[ -r /dev/tty && -w /dev/tty ]] || { printf '1\n'; return 0; }

  local old_stty row col pos
  old_stty="$(stty -g </dev/tty 2>/dev/null || true)"
  stty -echo -icanon time 1 min 0 </dev/tty 2>/dev/null || true
  printf '\033[6n' >/dev/tty
  IFS=';' read -r -t 0.05 -d R pos col </dev/tty || true
  [[ -n "$old_stty" ]] && stty "$old_stty" </dev/tty 2>/dev/null || true

  row="${pos#*[}"
  if [[ "$row" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$row"
  else
    printf '1\n'
  fi
}

menu_read_key() {
  local key seq flush
  if [[ -n "${MENU_KEY_PUSHBACK:-}" ]]; then
    key="$MENU_KEY_PUSHBACK"
    MENU_KEY_PUSHBACK=""
  else
    while IFS= read -rsn1 -t 0.001 flush; do
      [[ "$flush" == $'\r' || "$flush" == $'\n' ]] && continue
      key="$flush"
      break
    done
    if [[ -z "${key:-}" ]]; then
      if ! IFS= read -rsn1 key; then
        return 1
      fi
    fi
  fi

  if [[ "$key" == $'\e' ]]; then
    if ! IFS= read -rsn1 -t 0.02 seq; then
      printf 'esc\n'
      return 0
    fi
    if [[ "$seq" == "[" || "$seq" == "O" ]]; then
      if ! IFS= read -rsn1 -t 0.02 key; then
        printf 'esc\n'
        return 0
      fi
      case "$key" in
        A) printf 'up\n' ;;
        B) printf 'down\n' ;;
        C) printf 'right\n' ;;
        D) printf 'left\n' ;;
        H) printf 'home\n' ;;
        F) printf 'end\n' ;;
        M) printf 'enter\n' ;;
        5)
          IFS= read -rsn1 -t 0.005 flush || true
          printf 'pageup\n'
          ;;
        6)
          IFS= read -rsn1 -t 0.005 flush || true
          printf 'pagedown\n'
          ;;
        1|4|7|8)
          IFS= read -rsn1 -t 0.005 flush || true
          [[ "$key" == 1 || "$key" == 7 ]] && printf 'home\n' || printf 'end\n'
          ;;
        *) printf 'esc\n' ;;
      esac
      return 0
    fi
    MENU_KEY_PUSHBACK="$seq"
    printf 'esc\n'
    return 0
  fi

  case "$key" in
    ""|$'\r'|$'\n')
      IFS= read -rsn1 -t 0.005 flush || true
      [[ "$flush" == $'\r' || "$flush" == $'\n' ]] || MENU_KEY_PUSHBACK="${flush:-}"
      printf 'enter\n'
      ;;
    " ") printf 'space\n' ;;
    $'\t') printf 'tab\n' ;;
    [kK]) printf 'up\n' ;;
    [jJ]) printf 'down\n' ;;
    [hH]) printf 'left\n' ;;
    [lL]) printf 'right\n' ;;
    [bB]) printf 'back\n' ;;
    [sS]) printf 'skip\n' ;;
    [dD]) printf 'done\n' ;;
    [qQ]) printf 'char:%s\n' "$key" ;;
    *) printf 'char:%s\n' "$key" ;;
  esac
}

ui_clear() {
  [[ -t 2 ]] || return 0
  if command -v tput >/dev/null 2>&1; then
    if (( UI_STACK_DEPTH > 0 )); then
      tput cup 0 0 >&2
      tput ed >&2
    else
      tput ed >&2
    fi
  fi
}

ui_push() {
  [[ -t 2 ]] || return 1
  command -v tput >/dev/null 2>&1 || return 1
  tput civis >&2
  UI_STACK_DEPTH=$((UI_STACK_DEPTH + 1))
  ui_clear
  return 0
}

ui_pop() {
  [[ -t 2 ]] || return 1
  (( UI_STACK_DEPTH > 0 )) || return 1
  command -v tput >/dev/null 2>&1 || return 1
  tput cnorm >&2
  UI_STACK_DEPTH=$((UI_STACK_DEPTH - 1))
  return 0
}

truncate_text() {
  local text="$1"
  local max_len="${2:-70}"
  if (( ${#text} > max_len )); then
    printf '%s...' "${text:0:$((max_len - 3))}"
  else
    printf '%s' "$text"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local reply
  local prompt_main="$prompt"
  local prompt_info=""
  local yn_suffix=""

  if [[ "$prompt" =~ ^(.*)[[:space:]]\(([^()]*)\)$ ]]; then
    prompt_main="${BASH_REMATCH[1]}"
    prompt_info="${BASH_REMATCH[2]}"
  fi

  while true; do
    if [[ "$default" == "y" ]]; then
      yn_suffix="[${C_GREEN}Y${C_RESET}/${C_OVERLAY1}n${C_RESET}]"
      if ! read_prompt reply "$(printf '%b%s%b%s%b %s ' "$C_TEXT" "$prompt_main" "$C_RESET" "${prompt_info:+ ${C_SUBTEXT0}(${prompt_info})$C_RESET}" "$C_RESET" "$yn_suffix:")"; then
        return 1
      fi
      reply="${reply:-y}"
    else
      yn_suffix="[${C_OVERLAY1}y${C_RESET}/${C_GREEN}N${C_RESET}]"
      if ! read_prompt reply "$(printf '%b%s%b%s%b %s ' "$C_TEXT" "$prompt_main" "$C_RESET" "${prompt_info:+ ${C_SUBTEXT0}(${prompt_info})$C_RESET}" "$C_RESET" "$yn_suffix:")"; then
        return 1
      fi
      reply="${reply:-n}"
    fi
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) printf '%bPlease answer y or n.%b\n' "$C_PEACH" "$C_RESET" ;;
    esac
  done
}

ask_input_default() {
  local prompt="$1"
  local default="$2"
  local v
  read_prompt v "$(prompt_label "$prompt [$default]: ")"
  printf '%s\n' "${v:-$default}"
}

startup_resolve_python_bin() {
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3\n'
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    printf 'python\n'
    return 0
  fi
  return 1
}

startup_has_network() {
  ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 \
    || ping -c 1 -W 1 github.com >/dev/null 2>&1 \
    || ping -c 1 -W 1 archlinux.org >/dev/null 2>&1
}

startup_draw_box() {
  local title="$1"
  shift
  ui_clear
  {
  printf '%b' "$C_BOLD$C_PEACH"
  cat <<'EOF'
    █████╗ ██████╗  ██████╗████████╗██╗   ██╗██╗  ██╗
   ██╔══██╗██╔══██╗██╔════╝╚══██╔══╝╚██╗ ██╔╝╚██╗██╔╝
   ███████║██████╔╝██║        ██║    ╚████╔╝  ╚███╔╝
   ██╔══██║██╔══██╗██║        ██║     ╚██╔╝   ██╔██╗
   ██║  ██║██║  ██║╚██████╗   ██║      ██║   ██╔╝ ██╗
   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝
EOF
  printf '%b\n\n' "$C_RESET"
  printf '%b%s%b\n' "$C_BOLD$C_PEACH" "$title" "$C_RESET"
  printf '%b%s%b\n' "$C_SUBTEXT0" "A modern, modular system setup tool" "$C_RESET"
  printf '\n'
  while (($#)); do
    printf '%b%s%b\n' "$C_TEXT" "$1" "$C_RESET"
    shift
  done
  } >&2
}

startup_draw_option_rows() {
  local selected_index="$1"
  shift
  local entries=("$@")
  local i entry label desc prefix
  local label_color desc_color cols label_width desc_width
  local max_label=0

  cols="$(tput cols 2>/dev/null || echo 80)"
  for entry in "${entries[@]}"; do
    label="${entry%%|*}"
    (( ${#label} > max_label )) && max_label=${#label}
  done

  label_width=$(( max_label + 4 ))
  (( label_width < 16 )) && label_width=16
  (( label_width > 24 )) && label_width=24
  desc_width=$(( cols - 7 - label_width ))
  (( desc_width < 16 )) && desc_width=16

  for i in "${!entries[@]}"; do
    entry="${entries[$i]}"
    label="${entry%%|*}"
    if [[ "$entry" == *"|"* ]]; then
      desc="${entry#*|}"
    else
      desc=""
    fi

    prefix=' '
    label_color="$C_ROSEWATER"
    desc_color="$C_OVERLAY1"
    if [[ "$i" -eq "$selected_index" ]]; then
      prefix='>'
      label_color="$C_BOLD$C_PEACH"
      desc_color="$C_BOLD$C_PEACH"
    fi

    tput rc >&2
    (( i > 0 )) && tput cud "$i" >&2
    tput el >&2
    printf ' %s %b%-*s%b %b%s%b' \
      "$prefix" \
      "$label_color" "$label_width" "$(truncate_text "$label" "$label_width")" "$C_RESET" \
      "$desc_color" "$(truncate_text "$desc" "$desc_width")" "$C_RESET" >&2
  done
}

startup_choose_option() {
  local title="$1"
  local message="$2"
  shift 2
  local options=("$@")
  local index=0
  local key

  STARTUP_MENU_SELECTION=""
  startup_draw_box \
    "$title" \
    "$message"
  printf '%b%s%b\n' "$C_SUBTEXT0" "Use ↑/↓ (or j/k) and Enter to select." "$C_RESET" >&2
  printf '\n' >&2
  tput sc >&2
  while true; do
    startup_draw_option_rows "$index" "${options[@]}"
    tput rc >&2
    tput cud "${#options[@]}" >&2
    tput el >&2
    printf '\n%b%s%b\n' "$C_SUBTEXT0" "Enter = Select • ESC/Q = Exit" "$C_RESET" >&2

    key="$(menu_read_key || true)"
    case "$key" in
      up)
        index=$(((index - 1 + ${#options[@]}) % ${#options[@]}))
        ;;
      down)
        index=$(((index + 1) % ${#options[@]}))
        ;;
      enter|right|space)
        STARTUP_MENU_SELECTION="$index"
        return 0
        ;;
      esc|back|char:q|char:Q)
        STARTUP_MENU_SELECTION="$(( ${#options[@]} - 1 ))"
        return 0
        ;;
    esac
  done
}

startup_wait_for_network() {
  local pushed="no"
  ui_push && pushed="yes"
  while ! startup_has_network; do
    startup_choose_option \
      "Network Required" \
      "Please connect to the internet and retry." \
      "Retry|Check the connection again and continue setup" \
      "Exit|Close ARCTYX until internet is available"
    case "$STARTUP_MENU_SELECTION" in
      0) ;;
      *)
        [[ "$pushed" == "yes" ]] && ui_pop
        return 1
        ;;
    esac
  done
  [[ "$pushed" == "yes" ]] && ui_pop
  return 0
}

startup_collect_missing_dependencies() {
  local missing=()
  local python_bin=""
  python_bin="$(startup_resolve_python_bin || true)"
  if [[ -z "$python_bin" ]]; then
    missing+=("python")
  fi
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  printf '%s\n' "${missing[*]:-}"
}

startup_install_missing_dependencies() {
  local missing=("$@")
  local log_file spinner_pid rc frame_idx
  local frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )

  startup_wait_for_network || return 1

  log_file="/tmp/arctyx-deps-install.$$.$RANDOM.log"
  : > "$log_file"

  (
    pacman -Sy --needed --noconfirm "${missing[@]}"
  ) >"$log_file" 2>&1 &
  spinner_pid=$!

  if command -v tput >/dev/null 2>&1; then
    tput civis >/dev/null 2>&1 || true
  fi

  frame_idx=0
  while kill -0 "$spinner_pid" >/dev/null 2>&1; do
    startup_draw_box \
      "Installing Missing Dependencies" \
      "Preparing runtime requirements for ARCTYX..." \
      "" \
      "Missing: ${missing[*]}" \
      "" \
      "${frames[$frame_idx]} Installing in background"
    frame_idx=$(((frame_idx + 1) % ${#frames[@]}))
    sleep 0.12
  done

  wait "$spinner_pid"
  rc=$?

  if command -v tput >/dev/null 2>&1; then
    tput cnorm >/dev/null 2>&1 || true
  fi

  if [[ "$rc" -ne 0 ]]; then
    startup_draw_box \
      "Dependency Installation Failed" \
      "ARCTYX could not install the required dependencies automatically." \
      "" \
      "Last output:" \
      "$(tail -n 8 "$log_file" 2>/dev/null | sed 's/\t/  /g')"
    printf '\n'
    return 1
  fi

  startup_draw_box \
    "Dependencies Ready" \
    "All required dependencies were installed successfully." \
    "" \
    "Installed: ${missing[*]}"
  sleep 0.8
  rm -f "$log_file"
  return 0
}

startup_prepare_runtime() {
  local missing_text
  local -a missing=()

  startup_wait_for_network || exit 1

  missing_text="$(startup_collect_missing_dependencies)"
  if [[ -n "$missing_text" ]]; then
    read -r -a missing <<<"$missing_text"
    startup_install_missing_dependencies "${missing[@]}" || {
      err "Failed to prepare required dependencies."
      exit 1
    }
  fi

  PYTHON_BIN="$(startup_resolve_python_bin || true)"
}

choose_menu() {
  local title="$1"
  shift
  local options=("$@")
  local i idx
  local has_back="no"
  local back_index=-1
  local has_skip="no"
  local skip_index=-1
  local has_done="no"
  local done_index=-1
  local allow_b_shortcut="no"
  local allow_s_shortcut="no"
  local allow_d_shortcut="no"
  local use_backstack="no"
  local __pushed="no"
  local keys=() descs=() statuses=() states=()
  [[ "$title" == "Select Display Manager" || "$title" == "Select Display Manager (explicit)" ]] && allow_b_shortcut="yes"
  [[ "$title" == "Shell Installation" || "$title" == "Select Login Method" || "$title" == "AUR Helper Choice (Step 2)" || "$title" == "Driver Installation Type" || "$title" == "File Manager Option" || "$title" == "AUR Packages Are Required; Choose Helper To Continue" ]] && allow_s_shortcut="yes"

  # Pre-scan options to discover shortcuts/disabled entries once.
  for i in "${!options[@]}"; do
    local key desc status state
    IFS='|' read -r key desc status state <<< "${options[$i]}"
    keys+=("$key")
    descs+=("$desc")
    statuses+=("${status:-}")
    states+=("${state:-}")
    if [[ "$key" == "Back" || "$key" == "back" ]]; then
      has_back="yes"
      back_index="$i"
    fi
    if [[ "${key,,}" == "skip" || "${key,,}" == "s" ]]; then
      has_skip="yes"
      skip_index="$i"
    fi
    if [[ "${key,,}" == "done" || "${key,,}" == "d" ]]; then
      has_done="yes"
      done_index="$i"
    fi
  done

  if [[ "$allow_b_shortcut" == "yes" ]]; then
    use_backstack="yes"
  fi
  [[ "$has_done" == "yes" ]] && allow_d_shortcut="yes"

  if [[ "$use_backstack" == "yes" ]] && ui_push; then
    __pushed="yes"
  fi

  if [[ -t 0 && -t 2 ]]; then
    local cursor=0
    local hint=""
    local selectable_count=0
    local saved_cursor=""
    local cursor_set="no"
    local cursor_hidden="no"
    local term_rows term_cols menu_h current_row available_rows panel_top

    if command -v tput >/dev/null 2>&1; then
      tput civis >&2 || true
      cursor_hidden="yes"
    fi

    menu_restore_cursor() {
      if [[ "$cursor_hidden" == "yes" ]] && command -v tput >/dev/null 2>&1; then
        tput cnorm >&2 || true
      fi
    }

    menu_leave_panel() {
      local r
      if [[ "${menu_h:-}" =~ ^[0-9]+$ ]] && (( menu_h > 0 )); then
        for ((r=0; r<menu_h; r++)); do
          tput rc >&2 || true
          (( r > 0 )) && tput cud "$r" >&2
          tput el >&2 || true
        done
      fi
      tput rc >&2 || true
      tput el >&2 || true
    }
    for i in "${!states[@]}"; do
      if [[ "${states[$i]}" != "disabled" ]]; then
        selectable_count=$((selectable_count + 1))
      fi
    done
    if (( selectable_count == 0 )); then
      menu_leave_panel
      menu_restore_cursor
      if [[ "$__pushed" == "yes" ]]; then
        ui_pop || true
      fi
      if [[ "$has_done" == "yes" ]]; then
        printf '%s\n' "${keys[$done_index]}"
        return 0
      fi
      if [[ "$has_skip" == "yes" ]]; then
        printf '%s\n' "${keys[$skip_index]}"
        return 0
      fi
      if [[ "$has_back" == "yes" ]]; then
        printf '%s\n' "${keys[$back_index]}"
        return 0
      fi
      printf '%s\n' ""
      return 0
    fi

    term_rows="$(tput lines 2>/dev/null || echo 24)"
    term_cols="$(tput cols 2>/dev/null || echo 80)"
    menu_h=$(( ${#keys[@]} + 5 ))
    if (( menu_h > term_rows - 1 )); then
      menu_h=$(( term_rows - 1 ))
    fi
    current_row="$(get_cursor_row)"
    if ! [[ "$current_row" =~ ^[0-9]+$ ]]; then
      current_row=1
    fi
    available_rows=$(( term_rows - current_row + 1 ))
    if (( available_rows < menu_h )); then
      panel_top=$(( term_rows - menu_h + 1 ))
      (( panel_top < 1 )) && panel_top=1
      tput cup $((panel_top - 1)) 0 >&2
    fi
    # Anchor menu panel at current cursor position.
    # If there is not enough room below, shift the panel upward to keep all rows visible.
    tput sc >&2

    menu_clear_panel() {
      local r
      for ((r=0; r<menu_h; r++)); do
        tput rc >&2
        (( r > 0 )) && tput cud "$r" >&2
        tput el >&2
      done
    }
    if [[ "${MENU_CURSOR_HINT:-}" =~ ^[0-9]+$ ]] && (( MENU_CURSOR_HINT >= 0 && MENU_CURSOR_HINT < ${#states[@]} )) && [[ "${states[$MENU_CURSOR_HINT]}" != "disabled" ]]; then
      cursor="$MENU_CURSOR_HINT"
      cursor_set="yes"
    fi
    if [[ "$cursor_set" != "yes" ]]; then
      saved_cursor="${MENU_CURSOR_MEMORY[$title]:-}"
      if [[ "$saved_cursor" =~ ^[0-9]+$ ]] && (( saved_cursor >= 0 && saved_cursor < ${#states[@]} )) && [[ "${states[$saved_cursor]}" != "disabled" ]]; then
        cursor="$saved_cursor"
      else
        for i in "${!states[@]}"; do
          if [[ "${states[$i]}" != "disabled" ]]; then
            cursor="$i"
            break
          fi
        done
      fi
    fi
    menu_clear_panel
    tput rc >&2
    printf '%b%s%b\n' "$C_BOLD$C_SKY" "$title" "$C_RESET" >&2
    printf '%bUse ↑/↓ (or j/k) and Enter to select.%b\n' "$C_SUBTEXT0" "$C_RESET" >&2
    [[ "$has_back" == "yes" || "$allow_b_shortcut" == "yes" ]] && hint="b=Back"
    [[ "$has_skip" == "yes" || "$allow_s_shortcut" == "yes" ]] && hint="${hint:+$hint, }s=Skip"
    [[ "$allow_d_shortcut" == "yes" ]] && hint="${hint:+$hint, }d=Done"
    [[ -n "$hint" ]] && printf '%b%s%b\n' "$C_SUBTEXT0" "$hint" "$C_RESET" >&2
    printf '\n' >&2
    # Save cursor at the start of the options block.
    tput sc >&2

    menu_draw_rows() {
      local row_i key desc status state prefix row_key_color row_desc_color row_status_color
      local cols desc_max desc_print key_max key_cap key_print
      local max_key_len max_status_len status_inner status_segment
      cols="$(tput cols 2>/dev/null || echo 80)"
      max_key_len=0
      max_status_len=0
      for key in "${keys[@]}"; do
        (( ${#key} > max_key_len )) && max_key_len=${#key}
      done
      for status in "${statuses[@]}"; do
        (( ${#status} > max_status_len )) && max_status_len=${#status}
      done

      key_cap=$(( cols / 3 ))
      (( key_cap < 14 )) && key_cap=14
      (( key_cap > 34 )) && key_cap=34
      key_max=$(( max_key_len + 2 ))
      (( key_max < 14 )) && key_max=14
      (( key_max > key_cap )) && key_max=$key_cap

      status_inner=0
      if (( max_status_len > 0 )); then
        status_inner=$(( max_status_len ))
        (( status_inner < 10 )) && status_inner=10
        (( status_inner > 14 )) && status_inner=14
      fi

      for row_i in "${!keys[@]}"; do
        key="${keys[$row_i]}"
        desc="${descs[$row_i]}"
        status="${statuses[$row_i]}"
        state="${states[$row_i]}"
        prefix=' '
        row_key_color="$C_ROSEWATER"
        row_desc_color="$C_OVERLAY1"
        row_status_color="$C_OVERLAY0"

        if [[ "$state" == "disabled" ]]; then
          row_key_color="$C_SURFACE0"
          row_desc_color="$C_SURFACE0"
          row_status_color="$C_SURFACE0"
        fi
        if [[ "$row_i" -eq "$cursor" && "$state" != "disabled" ]]; then
          prefix='>'
          row_key_color="$C_BOLD$C_SKY"
          row_desc_color="$C_TEXT"
        fi

        if [[ -n "$status" && "$state" != "disabled" ]]; then
          [[ "${status,,}" == "installed" ]] && row_status_color="$C_GREEN"
          [[ "${status,,}" == "not installed" ]] && row_status_color="$C_RED"
          [[ "${status,,}" == "to be installed" ]] && row_status_color="$C_YELLOW"
          [[ "${status,,}" == "selected" ]] && row_status_color="$C_TEAL"
        fi

        # Dynamic column sizing based on terminal width.
        # row prefix: " <marker> " = 3 chars
        status_segment=0
        if (( status_inner > 0 )); then
          # "[status] " => status_inner + 3
          status_segment=$(( status_inner + 3 ))
        fi
        desc_max=$(( cols - (3 + key_max + 1 + status_segment) ))
        (( desc_max < 10 )) && desc_max=10
        desc_print="$(truncate_text "$desc" "$desc_max")"
        key_print="$(truncate_text "$key" "$key_max")"

        tput rc >&2
        (( row_i > 0 )) && tput cud "$row_i" >&2
        tput el >&2
        printf ' %s %b%-*s%b ' "$prefix" "$row_key_color" "$key_max" "$key_print" "$C_RESET" >&2
        if (( status_inner > 0 )); then
          if [[ -n "$status" ]]; then
            printf '%b[%-*s]%b ' "$row_status_color" "$status_inner" "$(truncate_text "$status" "$status_inner")" "$C_RESET" >&2
          else
            printf '%*s' "$((status_inner + 3))" '' >&2
          fi
        fi
        printf '%b%s%b' "$row_desc_color" "$desc_print" "$C_RESET" >&2
      done
    }

    menu_draw_rows

    while true; do

      local nav_key
      local prev_cursor="$cursor"
      if ! nav_key="$(menu_read_key)"; then
        MENU_CURSOR_MEMORY["$title"]="$cursor"
        menu_leave_panel
        menu_restore_cursor
        if [[ "$__pushed" == "yes" ]]; then
          ui_pop || true
        fi
        if [[ "$has_done" == "yes" ]]; then
          printf '%s\n' "${keys[$done_index]}"
          return 0
        fi
        if [[ "$has_skip" == "yes" ]]; then
          printf '%s\n' "${keys[$skip_index]}"
          return 0
        fi
        printf '%s\n' ""
        return 0
      fi

      case "$nav_key" in
        up)
          local next="$cursor" tries=0
          while (( tries < ${#keys[@]} )); do
            next=$(( (next - 1 + ${#keys[@]}) % ${#keys[@]} ))
            [[ "${states[$next]}" != "disabled" ]] && { cursor="$next"; break; }
            tries=$((tries + 1))
          done
          ;;
        down|tab)
          local next="$cursor" tries=0
          while (( tries < ${#keys[@]} )); do
            next=$(( (next + 1) % ${#keys[@]} ))
            [[ "${states[$next]}" != "disabled" ]] && { cursor="$next"; break; }
            tries=$((tries + 1))
          done
          ;;
        home)
          for i in "${!keys[@]}"; do
            if [[ "${states[$i]}" != "disabled" ]]; then
              cursor="$i"
              break
            fi
          done
          ;;
        end)
          for ((i=${#keys[@]}-1; i>=0; i--)); do
            if [[ "${states[$i]}" != "disabled" ]]; then
              cursor="$i"
              break
            fi
          done
          ;;
        enter)
          if [[ "${states[$cursor]}" == "disabled" ]]; then
            continue
          fi
          MENU_CURSOR_MEMORY["$title"]="$cursor"
          menu_leave_panel
          menu_restore_cursor
          if [[ "$__pushed" == "yes" ]]; then
            ui_pop || true
          fi
          printf '%s\n' "${keys[$cursor]}"
          return 0
          ;;
        quit)
          MENU_CURSOR_MEMORY["$title"]="$cursor"
          menu_leave_panel
          menu_restore_cursor
          if [[ "$__pushed" == "yes" ]]; then
            ui_pop || true
          fi
          printf '%s\n' ""
          return 0
          ;;
        back|left|esc)
          if [[ "$has_back" == "yes" || "$allow_b_shortcut" == "yes" ]]; then
            MENU_CURSOR_MEMORY["$title"]="$cursor"
            menu_leave_panel
            menu_restore_cursor
            if [[ "$__pushed" == "yes" ]]; then
              ui_pop || true
            fi
            if [[ "$has_back" == "yes" ]]; then
              printf '%s\n' "${keys[$back_index]}"
            else
              printf '%s\n' "Back"
            fi
            return 0
          fi
          ;;
        skip)
          if [[ "$has_skip" == "yes" || "$allow_s_shortcut" == "yes" ]]; then
            MENU_CURSOR_MEMORY["$title"]="$cursor"
            menu_leave_panel
            menu_restore_cursor
            if [[ "$__pushed" == "yes" ]]; then
              ui_pop || true
            fi
            if [[ "$has_skip" == "yes" ]]; then
              printf '%s\n' "${keys[$skip_index]}"
            else
              printf '%s\n' "s"
            fi
            return 0
          fi
          ;;
        done)
          if [[ "$allow_d_shortcut" == "yes" ]]; then
            MENU_CURSOR_MEMORY["$title"]="$cursor"
            menu_leave_panel
            menu_restore_cursor
            if [[ "$__pushed" == "yes" ]]; then
              ui_pop || true
            fi
            printf '%s\n' "${keys[$done_index]}"
            return 0
          fi
          ;;
      esac

      if [[ "$cursor" -ne "$prev_cursor" ]]; then
        menu_draw_rows
      fi
    done
  fi

  while true; do
    if [[ "$has_back" == "yes" || "$allow_b_shortcut" == "yes" || "$has_skip" == "yes" || "$allow_s_shortcut" == "yes" || "$allow_d_shortcut" == "yes" ]]; then
      local extra=""
      [[ "$has_back" == "yes" || "$allow_b_shortcut" == "yes" ]] && extra="b=Back"
      [[ "$has_skip" == "yes" || "$allow_s_shortcut" == "yes" ]] && extra="${extra:+$extra, }s=Skip"
      [[ "$allow_d_shortcut" == "yes" ]] && extra="${extra:+$extra, }d=Done"
      if ! read_prompt idx "$(prompt_label "Select [1-${#options[@]}, ${extra}]: ")"; then
        if [[ "$__pushed" == "yes" ]]; then
          ui_pop || true
        fi
        if [[ "$has_done" == "yes" ]]; then
          printf '%s\n' "${options[$done_index]%%|*}"
          return 0
        fi
        if [[ "$has_skip" == "yes" ]]; then
          printf '%s\n' "${options[$skip_index]%%|*}"
          return 0
        fi
        printf '%s\n' ""
        return 0
      fi
      if [[ "${idx,,}" == "b" ]]; then
        if [[ "$__pushed" == "yes" ]]; then
          ui_pop || true
        fi
        if [[ "$has_back" == "yes" ]]; then
          printf '%s\n' "${options[$back_index]%%|*}"
        else
          printf '%s\n' "Back"
        fi
        return 0
      fi
      if [[ "${idx,,}" == "s" && ( "$has_skip" == "yes" || "$allow_s_shortcut" == "yes" ) ]]; then
        if [[ "$__pushed" == "yes" ]]; then
          ui_pop || true
        fi
        if [[ "$has_skip" == "yes" ]]; then
          printf '%s\n' "${options[$skip_index]%%|*}"
        else
          printf '%s\n' "s"
        fi
        return 0
      fi
      if [[ "${idx,,}" == "d" && "$allow_d_shortcut" == "yes" ]]; then
        if [[ "$__pushed" == "yes" ]]; then
          ui_pop || true
        fi
        printf '%s\n' "${options[$done_index]%%|*}"
        return 0
      fi
    else
      if ! read_prompt idx "$(prompt_label "Select [1-${#options[@]}]: ")"; then
        if [[ "$__pushed" == "yes" ]]; then
          ui_pop || true
        fi
        printf '%s\n' ""
        return 0
      fi
    fi
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#options[@]} )); then
      local selected_key selected_state
      selected_key="${keys[$((idx - 1))]}"
      selected_state="${states[$((idx - 1))]}"
      if [[ "${selected_state:-}" == "disabled" ]]; then
        printf '%b%s%b\n' "$C_PEACH" "This option is disabled." "$C_RESET" >&2
        continue
      fi
      if [[ "$__pushed" == "yes" ]]; then
        ui_pop || true
      fi
      printf '%s\n' "$selected_key"
      return 0
    fi
    ui_invalid_selection >&2
  done
}

refresh_user_context() {
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  TARGET_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7 || true)"

  if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    err "Unable to resolve valid home for user: $TARGET_USER"
    exit 1
  fi
  if [[ -z "$TARGET_SHELL" ]]; then
    TARGET_SHELL="/bin/bash"
  fi

  local shell_base
  shell_base="$(basename "$TARGET_SHELL")"
  case "$shell_base" in
    fish) SHELL_RC_FILE="$TARGET_HOME/.config/fish/config.fish" ;;
    zsh) SHELL_RC_FILE="$TARGET_HOME/.zprofile" ;;
    bash) SHELL_RC_FILE="$TARGET_HOME/.bash_profile" ;;
    *) SHELL_RC_FILE="$TARGET_HOME/.profile" ;;
  esac
}

ensure_pacman_db_ready() {
  local sync_dir="/var/lib/pacman/sync"
  if compgen -G "${sync_dir}/*.db" >/dev/null 2>&1; then
    return 0
  fi
  warn "Pacman sync database not found. Running pacman -Sy once before install."
  pacman -Sy --noconfirm || {
    err "Failed to initialize pacman sync database."
    return 1
  }
}

package_exists_in_pacman_repos() {
  pacman -Si "$1" >/dev/null 2>&1
}

pick_available_aur_helper_for_validation() {
  if [[ "$ARCH_AUR_HELPER" == "yay" || "$ARCH_AUR_HELPER" == "paru" ]]; then
    printf '%s\n' "$ARCH_AUR_HELPER"
    return 0
  fi
  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
    return 0
  fi
  if command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
    return 0
  fi
  return 1
}

package_exists_in_aur() {
  local helper="$1"
  local pkg="$2"
  [[ -n "$helper" ]] || return 2
  run_as_target_user_argv "$helper" -Si "$pkg" >/dev/null 2>&1
}

package_exists_in_aur_rpc() {
  local pkg="$1"
  local response
  [[ -n "$pkg" ]] || return 1
  command -v curl >/dev/null 2>&1 || return 2

  response="$(curl -fsSL --get \
    --data-urlencode 'v=5' \
    --data-urlencode 'type=info' \
    --data-urlencode "arg[]=$pkg" \
    'https://aur.archlinux.org/rpc/' 2>/dev/null || true)"

  [[ -n "$response" ]] || return 2
  [[ "$response" == *'"type":"error"'* ]] && return 2
  [[ "$response" == *'"resultcount":0'* ]] && return 1
  [[ "$response" == *'"resultcount":1'* ]] && return 0
  [[ "$response" =~ \"resultcount\":[[:space:]]*([0-9]+) ]] || return 2
  (( BASH_REMATCH[1] > 0 )) && return 0
  return 1
}

handle_invalid_custom_packages() {
  local invalid_list="$1"
  [[ -n "$invalid_list" ]] || return 0

  warn "Some custom packages were not found and cannot be installed: $invalid_list"
  if ask_yes_no "Skip invalid custom packages and continue" y; then
    ARCH_CUSTOM_APP_PKGS_SKIPPED="$invalid_list"
    log "Skipping invalid custom packages: $invalid_list"
    return 0
  fi

  err "Aborted because invalid custom packages were provided: $invalid_list"
  return 1
}

resolve_valid_custom_app_packages() {
  local -a valid_pac=()
  local -a valid_aur=()
  local -a invalid=()
  local cpkg helper aur_pkg

  helper="$(pick_available_aur_helper_for_validation || true)"
  ARCH_CUSTOM_APP_PKGS_INVALID=""
  ARCH_CUSTOM_APP_PKGS_SKIPPED=""
  ARCH_CUSTOM_APP_PKGS_VALID_PACMAN=""
  ARCH_CUSTOM_APP_PKGS_VALID_AUR=""
  AUR_RPC_VALIDATION_UNAVAILABLE="no"

  for cpkg in $ARCH_CUSTOM_APP_PKGS; do
    [[ -n "$cpkg" ]] || continue
    if [[ "$cpkg" == aur:* ]]; then
      aur_pkg="${cpkg#aur:}"
      if [[ -z "$aur_pkg" ]]; then
        invalid+=("$cpkg")
      elif [[ -n "$helper" ]]; then
        if package_exists_in_aur "$helper" "$aur_pkg"; then
          valid_aur+=("$aur_pkg")
        else
          invalid+=("$cpkg")
        fi
      else
        if package_exists_in_aur_rpc "$aur_pkg"; then
          valid_aur+=("$aur_pkg")
        else
          case $? in
            1) invalid+=("$cpkg") ;;
            2)
              AUR_RPC_VALIDATION_UNAVAILABLE="yes"
              valid_aur+=("$aur_pkg")
              ;;
          esac
        fi
      fi
    else
      if package_exists_in_pacman_repos "$cpkg"; then
        valid_pac+=("$cpkg")
      else
        invalid+=("$cpkg")
      fi
    fi
  done

  ARCH_CUSTOM_APP_PKGS_INVALID="${invalid[*]}"
  ARCH_CUSTOM_APP_PKGS_VALID_PACMAN="${valid_pac[*]}"
  ARCH_CUSTOM_APP_PKGS_VALID_AUR="${valid_aur[*]}"

  if [[ "$AUR_RPC_VALIDATION_UNAVAILABLE" == "yes" && -z "$helper" ]]; then
    warn "AUR custom package validation is temporarily unavailable (missing helper and AUR RPC could not be verified). AUR custom packages will be validated during install."
  fi
}

ensure_os_prober_installed() {
  if command -v os-prober >/dev/null 2>&1; then
    return 0
  fi

  warn "os-prober not found. Installing os-prober..."
  ensure_pacman_db_ready || return 1
  if ! pacman -S --needed --noconfirm os-prober; then
    warn "Failed to install os-prober."
    return 1
  fi

  if ! command -v os-prober >/dev/null 2>&1; then
    warn "os-prober installation completed but command is still unavailable."
    return 1
  fi
  log "os-prober installed successfully."
}

ensure_os_prober_prereqs() {
  ensure_pacman_db_ready || return 1
  # ntfs-3g helps os-prober inspect common Windows NTFS volumes.
  # dosfstools/util-linux aid partition probing workflows on some systems.
  if ! pacman -S --needed --noconfirm ntfs-3g dosfstools util-linux >/dev/null 2>&1; then
    warn "Failed to install one or more os-prober prerequisite packages (ntfs-3g/dosfstools/util-linux)."
    return 1
  fi
}

run_os_prober_with_diagnostics() {
  local out_file="/tmp/setup-osprober-${TS}.log"
  : > "$out_file"
  if ! os-prober >"$out_file" 2>&1; then
    warn "os-prober failed. Output:"
    sed 's/^/  /' "$out_file" || true
    rm -f "$out_file"
    return 1
  fi

  if [[ ! -s "$out_file" ]]; then
    warn "os-prober returned no detected OS entries."
    warn "Common causes: Windows Fast Startup enabled, BitLocker-encrypted Windows partition, or UEFI/Legacy boot-mode mismatch."
    rm -f "$out_file"
    return 1
  fi

  log "os-prober detected entries:"
  sed 's/^/  /' "$out_file" || true
  rm -f "$out_file"
  return 0
}

detect_environment() {
  local wdir="/usr/share/wayland-sessions"
  local xdir="/usr/share/xsessions"

  if ls "$wdir"/hyprland*.desktop >/dev/null 2>&1 || ls "$xdir"/hyprland*.desktop >/dev/null 2>&1; then
    DETECTED_HYPRLAND="yes"
  fi
  if ls "$wdir"/plasma*.desktop >/dev/null 2>&1 || ls "$xdir"/plasma*.desktop >/dev/null 2>&1 || ls "$xdir"/kde-plasma*.desktop >/dev/null 2>&1; then
    DETECTED_PLASMA="yes"
  fi
  if ls "$wdir"/gnome*.desktop >/dev/null 2>&1 || ls "$xdir"/gnome*.desktop >/dev/null 2>&1; then
    DETECTED_GNOME="yes"
  fi
  if ls "$xdir"/xfce*.desktop >/dev/null 2>&1 || ls "$xdir"/xfce4*.desktop >/dev/null 2>&1; then
    DETECTED_XFCE="yes"
  fi

  for dm in gdm sddm lightdm; do
    if systemctl is-enabled "$dm" >/dev/null 2>&1 || systemctl is-active "$dm" >/dev/null 2>&1; then
      DETECTED_DM="$dm"
      break
    fi
  done
}

parse_cli_args() {
  local opt
  while getopts ":h" opt; do
    case "$opt" in
      h)
        cat <<'EOF'
Usage: setup.sh
  Launches the Arctyx modular wizard.

For non-interactive backend actions, use:
  python setup/main.py --action plan
  python setup/main.py --action apply
  python setup/main.py --action rollback
  python setup/main.py --action uninstall
EOF
        exit 0
        ;;
      :)
        err "Option -$OPTARG requires an argument."
        exit 1
        ;;
      \?)
        err "Unknown option: -$OPTARG"
        exit 1
        ;;
    esac
  done
}

list_has() {
  local list="$1"
  local needle="$2"
  local x
  for x in $list; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

category_packages() {
  case "$1" in
    core-system) echo "base-devel git curl wget ca-certificates openssh rsync unzip zip tar gzip bzip2 xz man-db man-pages" ;;
    dev-toolchain) echo "gcc make cmake meson ninja pkgconf python python-pip nodejs npm go rustup" ;;
    shells) echo "bash-completion zsh-completions zsh-autosuggestions zsh-syntax-highlighting" ;;
    cli-utils) echo "ripgrep fd fzf bat eza tree jq yq htop btop ncdu tmux neovim nano fastfetch" ;;
    networking) echo "networkmanager network-manager-applet dnsutils inetutils nmap traceroute" ;;
    desktop-common) echo "xdg-utils gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-gphoto2 gvfs-nfs file-roller p7zip unarchiver" ;;
    media) echo "ffmpeg imagemagick ffmpegthumbnailer" ;;
    fonts) echo "ttf-dejavu noto-fonts noto-fonts-emoji" ;;
    containers) echo "docker docker-compose podman" ;;
    desktop-wm) echo "" ;;
    *) echo "" ;;
  esac
}

de_packages() {
  local session="${1:-none}"
  local profile="${2:-core}"
  case "$session:$profile" in
    hyprland:core) echo "hyprland xdg-desktop-portal-hyprland" ;;
    hyprland:full) echo "hyprland xdg-desktop-portal-hyprland waybar wofi kitty sddm" ;;
    sway:core) echo "sway xdg-desktop-portal-wlr" ;;
    sway:full) echo "sway xdg-desktop-portal-wlr waybar wofi foot sddm" ;;
    river:core) echo "river xdg-desktop-portal-wlr" ;;
    river:full) echo "river xdg-desktop-portal-wlr waybar wofi foot sddm" ;;
    wayfire:core) echo "wayfire xdg-desktop-portal-wlr" ;;
    wayfire:full) echo "wayfire wayfire-plugins-extra xdg-desktop-portal-wlr wf-shell wcm foot sddm" ;;
    labwc:core) echo "labwc xdg-desktop-portal-wlr" ;;
    labwc:full) echo "labwc xdg-desktop-portal-wlr waybar wofi foot sddm" ;;
    niri:core) echo "niri xdg-desktop-portal-gnome" ;;
    niri:full) echo "niri xdg-desktop-portal-gnome waybar fuzzel foot sddm" ;;
    plasma:core) echo "plasma-desktop" ;;
    plasma:full) echo "plasma-meta konsole dolphin sddm" ;;
    gnome:core) echo "gnome-shell gnome-session" ;;
    gnome:full) echo "gnome gdm" ;;
    xfce:core) echo "xfce4 xfce4-session" ;;
    xfce:full) echo "xfce4 xfce4-goodies lightdm lightdm-gtk-greeter" ;;
    cinnamon:core) echo "cinnamon" ;;
    cinnamon:full) echo "cinnamon nemo lightdm lightdm-gtk-greeter" ;;
    mate:core) echo "mate" ;;
    mate:full) echo "mate mate-extra lightdm lightdm-gtk-greeter" ;;
    lxqt:core) echo "lxqt" ;;
    lxqt:full) echo "lxqt sddm" ;;
    budgie:core) echo "budgie-desktop" ;;
    budgie:full) echo "budgie-desktop gdm" ;;
    deepin:core) echo "deepin" ;;
    deepin:full) echo "deepin deepin-extra lightdm lightdm-gtk-greeter" ;;
    pantheon:core) echo "pantheon-session gala wingpanel" ;;
    pantheon:full) echo "pantheon-session gala wingpanel lightdm lightdm-pantheon-greeter" ;;
    i3:core) echo "i3-wm i3status i3lock dmenu" ;;
    i3:full) echo "i3-wm i3status i3lock dmenu picom feh rofi lightdm lightdm-gtk-greeter" ;;
    bspwm:core) echo "bspwm sxhkd" ;;
    bspwm:full) echo "bspwm sxhkd polybar rofi picom lightdm lightdm-gtk-greeter" ;;
    awesome:core) echo "awesome" ;;
    awesome:full) echo "awesome rofi picom lightdm lightdm-gtk-greeter" ;;
    openbox:core) echo "openbox obconf tint2" ;;
    openbox:full) echo "openbox obconf tint2 rofi picom lightdm lightdm-gtk-greeter" ;;
    custom:*) echo "$ARCH_CUSTOM_DE_PKGS" ;;
    none:*) echo "" ;;
    *) echo "" ;;
  esac
}

session_label() {
  case "$1" in
    hyprland) echo "Hyprland" ;;
    sway) echo "Sway" ;;
    river) echo "River" ;;
    wayfire) echo "Wayfire" ;;
    labwc) echo "Labwc" ;;
    niri) echo "Niri" ;;
    plasma) echo "Plasma" ;;
    gnome) echo "GNOME" ;;
    xfce) echo "XFCE" ;;
    cinnamon) echo "Cinnamon" ;;
    mate) echo "MATE" ;;
    lxqt) echo "LXQt" ;;
    budgie) echo "Budgie" ;;
    deepin) echo "Deepin" ;;
    pantheon) echo "Pantheon" ;;
    i3) echo "i3" ;;
    bspwm) echo "Bspwm" ;;
    awesome) echo "Awesome" ;;
    openbox) echo "Openbox" ;;
    custom) echo "Custom" ;;
    *) echo "$1" ;;
  esac
}

default_dm_for_session() {
  case "$1" in
    plasma|lxqt|hyprland|sway|river|wayfire|labwc|niri) echo "sddm" ;;
    gnome|budgie) echo "gdm" ;;
    xfce|cinnamon|mate|deepin|pantheon|i3|bspwm|awesome|openbox) echo "lightdm" ;;
    *) echo "none" ;;
  esac
}

ide_to_pkg() {
  case "$1" in
    code) echo "pacman|code" ;;
    codium) echo "aur|vscodium-bin" ;;
    cursor) echo "aur|cursor-bin" ;;
    zed) echo "pacman|zed" ;;
    neovim) echo "pacman|neovim" ;;
    emacs) echo "pacman|emacs" ;;
    helix) echo "pacman|helix" ;;
    sublime-text) echo "aur|sublime-text-4" ;;
    jetbrains-toolbox) echo "aur|jetbrains-toolbox" ;;
    *) echo "" ;;
  esac
}

app_to_pkg() {
  case "$1" in
    thunar) echo "pacman|thunar" ;;
    nautilus) echo "pacman|nautilus" ;;
    dolphin) echo "pacman|dolphin" ;;
    pcmanfm) echo "pacman|pcmanfm" ;;
    nemo) echo "pacman|nemo" ;;
    krusader) echo "pacman|krusader" ;;
    ranger) echo "pacman|ranger" ;;
    yazi) echo "pacman|yazi" ;;
    kitty) echo "pacman|kitty" ;;
    alacritty) echo "pacman|alacritty" ;;
    wezterm) echo "pacman|wezterm" ;;
    foot) echo "pacman|foot" ;;
    ghostty) echo "pacman|ghostty" ;;
    firefox) echo "pacman|firefox" ;;
    chromium) echo "pacman|chromium" ;;
    chrome) echo "aur|google-chrome" ;;
    brave) echo "aur|brave-bin" ;;
    waterfox) echo "aur|waterfox-bin" ;;
    zen) echo "aur|zen-browser-bin" ;;
    librewolf) echo "aur|librewolf-bin" ;;
    floorp) echo "aur|floorp-bin" ;;
    qutebrowser) echo "pacman|qutebrowser" ;;
    vivaldi) echo "pacman|vivaldi" ;;
    vlc) echo "pacman|vlc" ;;
    mpv) echo "pacman|mpv" ;;
    gimp) echo "pacman|gimp" ;;
    krita) echo "pacman|krita" ;;
    inkscape) echo "pacman|inkscape" ;;
    darktable) echo "pacman|darktable" ;;
    kdenlive) echo "pacman|kdenlive" ;;
    shotcut) echo "aur|shotcut-bin" ;;
    davinci-resolve) echo "aur|davinci-resolve" ;;
    obs-studio) echo "pacman|obs-studio" ;;
    blender) echo "pacman|blender" ;;
    audacity) echo "pacman|audacity" ;;
    handbrake) echo "pacman|handbrake" ;;
    telegram-desktop) echo "pacman|telegram-desktop" ;;
    signal-desktop) echo "pacman|signal-desktop" ;;
    element-desktop) echo "pacman|element-desktop" ;;
    vesktop) echo "aur|vesktop-bin" ;;
    slack-desktop) echo "aur|slack-desktop-wayland" ;;
    ferdium) echo "aur|ferdium-bin" ;;
    zoom) echo "aur|zoom" ;;
    localsend) echo "aur|localsend-bin" ;;
    balena-etcher) echo "aur|balena-etcher-bin" ;;
    ventoy) echo "aur|ventoy-bin" ;;
    freedownloadmanager) echo "aur|freedownloadmanager" ;;
    ab-download-manager) echo "aur|ab-download-manager-bin" ;;
    xdman) echo "aur|xdman" ;;
    gparted) echo "pacman|gparted" ;;
    baobab) echo "pacman|baobab" ;;
    filezilla) echo "pacman|filezilla" ;;
    syncthing) echo "pacman|syncthing" ;;
    kdeconnect) echo "pacman|kdeconnect" ;;
    keepassxc) echo "pacman|keepassxc" ;;
    flameshot) echo "pacman|flameshot" ;;
    remmina) echo "pacman|remmina" ;;
    qbittorrent) echo "pacman|qbittorrent" ;;
    timeshift) echo "pacman|timeshift" ;;
    flatseal) echo "pacman|flatseal" ;;
    spotify) echo "aur|spotify" ;;
    strawberry) echo "pacman|strawberry" ;;
    amberol) echo "pacman|amberol" ;;
    cmus) echo "pacman|cmus" ;;
    easyeffects) echo "pacman|easyeffects" ;;
    pavucontrol) echo "pacman|pavucontrol" ;;
    gitui) echo "pacman|gitui" ;;
    lazygit) echo "pacman|lazygit" ;;
    meld) echo "pacman|meld" ;;
    docker-desktop) echo "aur|docker-desktop" ;;
    steam) echo "pacman|steam" ;;
    wine) echo "pacman|wine" ;;
    lutris) echo "pacman|lutris" ;;
    gamemode) echo "pacman|gamemode" ;;
    mangohud) echo "pacman|mangohud" ;;
    heroic) echo "aur|heroic-games-launcher-bin" ;;
    prismlauncher) echo "pacman|prismlauncher" ;;
    bottles) echo "aur|bottles" ;;
    discord) echo "pacman|discord" ;;
    goverlay) echo "pacman|goverlay" ;;
    obsidian) echo "pacman|obsidian" ;;
    libreoffice-fresh) echo "pacman|libreoffice-fresh" ;;
    onlyoffice-bin) echo "aur|onlyoffice-bin" ;;
    thunderbird) echo "pacman|thunderbird" ;;
    okular) echo "pacman|okular" ;;
    evince) echo "pacman|evince" ;;
    joplin) echo "aur|joplin-desktop" ;;
    zathura) echo "pacman|zathura" ;;
    calibre) echo "pacman|calibre" ;;
    foliate) echo "pacman|foliate" ;;
    papers) echo "pacman|papers" ;;
    *) echo "" ;;
  esac
}

is_file_manager_app() {
  case "$1" in
    thunar|nautilus|dolphin|pcmanfm|nemo) return 0 ;;
    *) return 1 ;;
  esac
}

file_manager_support_packages() {
  case "$1" in
    thunar) echo "thunar-volman thunar-archive-plugin thunar-media-tags-plugin tumbler ffmpegthumbnailer gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-gphoto2 gvfs-nfs exo file-roller p7zip unarchiver xarchiver" ;;
    nautilus) echo "gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-gphoto2 gvfs-nfs sushi file-roller p7zip unarchiver" ;;
    dolphin) echo "konsole kio-extras ark ffmpegthumbnailer kdegraphics-thumbnailers" ;;
    pcmanfm) echo "gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-gphoto2 gvfs-nfs file-roller p7zip" ;;
    nemo) echo "nemo-fileroller gvfs gvfs-mtp gvfs-smb gvfs-afc gvfs-gphoto2 gvfs-nfs file-roller p7zip" ;;
    *) echo "" ;;
  esac
}

optimize_pacman_mirrors_if_selected() {
  [[ "$ARCH_OPTIMIZE_MIRRORS" == "yes" ]] || return 0
  log "Optimizing pacman mirrors with reflector"
  pacman -S --needed --noconfirm reflector
  reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || warn "Reflector run failed; keeping current mirrorlist."
  pacman -Syy || warn "pacman -Syy failed after reflector."
}

enable_repo_block() {
  local repo="$1"
  local conf="/etc/pacman.conf"

  if grep -Eq "^[[:space:]]*\\[$repo\\][[:space:]]*$" "$conf"; then
    log "Repository already enabled: $repo"
    return 0
  fi

  if grep -Eq "^[[:space:]]*#\\s*\\[$repo\\][[:space:]]*$" "$conf"; then
    log "Enabling repository block from commented config: $repo"
    python3 - "$conf" "$repo" <<'PY'
from pathlib import Path
import sys

conf = Path(sys.argv[1])
repo = sys.argv[2]
lines = conf.read_text().splitlines()
out = []
inside = False

for line in lines:
    stripped = line.lstrip()
    if stripped == f"#[{repo}]":
        out.append(line.replace(f"#[{repo}]", f"[{repo}]", 1))
        inside = True
        continue

    if inside:
        if stripped.startswith("#["):
            inside = False
        elif stripped.startswith("#Include =") or stripped.startswith("#Server =") or stripped.startswith("#SigLevel ="):
            prefix_len = len(line) - len(stripped)
            out.append(" " * prefix_len + stripped[1:])
            continue

    out.append(line)

conf.write_text("\n".join(out) + "\n")
PY
    return 0
  fi

  log "Appending repository block: $repo"
  cat >> "$conf" <<EOF

[$repo]
Include = /etc/pacman.d/mirrorlist
EOF
}

enable_selected_repositories_if_needed() {
  local changed="no"
  if [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]]; then
    enable_repo_block "multilib"
    changed="yes"
  fi
  if [[ "$ARCH_ENABLE_CORE_TESTING" == "yes" ]]; then
    enable_repo_block "core-testing"
    changed="yes"
  fi
  if [[ "$ARCH_ENABLE_EXTRA_TESTING" == "yes" ]]; then
    enable_repo_block "extra-testing"
    changed="yes"
  fi
  if [[ "$ARCH_ENABLE_MULTILIB_TESTING" == "yes" ]]; then
    enable_repo_block "multilib-testing"
    changed="yes"
  fi

  if [[ "$changed" == "yes" ]]; then
    log "Refreshing package database after repository changes"
    pacman -Syy || warn "pacman -Syy failed after repository updates."
  fi
}

enable_chaotic_aur_if_selected() {
  [[ "$ARCH_ENABLE_CHAOTIC_AUR" == "yes" ]] || return 0

  if grep -Eq '^\s*\[chaotic-aur\]\s*$' /etc/pacman.conf 2>/dev/null; then
    log "Chaotic AUR repo already present in /etc/pacman.conf"
    return 0
  fi

  log "Enabling Chaotic AUR repository"
  pacman -S --needed --noconfirm gnupg archlinux-keyring curl
  pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  pacman-key --lsign-key 3056513887B78AEB
  pacman -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

  cat >> /etc/pacman.conf <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

  pacman -Syy
}

resolve_arch_plan() {
  local pacman_pkgs=()
  local aur_pkgs=()
  local cat pkg ide mapped src name
  local selected_file_manager="no"

  for cat in $ARCH_SELECTED_CATEGORIES; do
    for pkg in $(category_packages "$cat"); do
      [[ -n "$pkg" ]] && pacman_pkgs+=("$pkg")
    done
  done
  [[ "$ARCH_INSTALL_FISH" == "yes" ]] && pacman_pkgs+=(fish)
  if [[ "$ARCH_INSTALL_ZSH" == "yes" ]]; then
    pacman_pkgs+=(zsh bash-completion zsh-completions zsh-autosuggestions zsh-syntax-highlighting)
  else
    pacman_pkgs+=(bash-completion)
  fi

  for ide in $ARCH_SELECTED_IDES; do
    mapped="$(ide_to_pkg "$ide")"
    [[ -z "$mapped" ]] && continue
    src="${mapped%%|*}"
    name="${mapped#*|}"
    if [[ "$src" == "aur" ]]; then
      aur_pkgs+=("$name")
    else
      pacman_pkgs+=("$name")
    fi
  done

  local app
  for app in $ARCH_SELECTED_APPS; do
    if is_file_manager_app "$app"; then
      selected_file_manager="yes"
      for pkg in $(file_manager_support_packages "$app"); do
        [[ -n "$pkg" ]] && pacman_pkgs+=("$pkg")
      done
    fi

    mapped="$(app_to_pkg "$app")"
    [[ -z "$mapped" ]] && continue
    src="${mapped%%|*}"
    name="${mapped#*|}"
    if [[ "$src" == "aur" ]]; then
      aur_pkgs+=("$name")
    else
      pacman_pkgs+=("$name")
    fi
  done

  if [[ "$selected_file_manager" == "yes" ]]; then
    local fm_auth_pkg
    fm_auth_pkg="$(resolve_auth_agent_pkg)"
    [[ -n "$fm_auth_pkg" ]] && pacman_pkgs+=("$fm_auth_pkg")
  fi

  resolve_valid_custom_app_packages || return 1
  if [[ -n "$ARCH_CUSTOM_APP_PKGS_INVALID" ]]; then
    handle_invalid_custom_packages "$ARCH_CUSTOM_APP_PKGS_INVALID" || return 1
  fi

  if [[ -n "$ARCH_CUSTOM_APP_PKGS_VALID_PACMAN" ]]; then
    local -a custom_pac_pkgs=()
    # shellcheck disable=SC2206
    custom_pac_pkgs=($ARCH_CUSTOM_APP_PKGS_VALID_PACMAN)
    pacman_pkgs+=("${custom_pac_pkgs[@]}")
  fi

  if [[ -n "$ARCH_CUSTOM_APP_PKGS_VALID_AUR" ]]; then
    local -a custom_aur_pkgs=()
    # shellcheck disable=SC2206
    custom_aur_pkgs=($ARCH_CUSTOM_APP_PKGS_VALID_AUR)
    aur_pkgs+=("${custom_aur_pkgs[@]}")
  fi

  for pkg in $(de_packages "$ARCH_SELECTED_DE"); do
    [[ -n "$pkg" ]] && pacman_pkgs+=("$pkg")
  done

  local -A seen=()
  local uniq_pac=()
  for pkg in "${pacman_pkgs[@]}"; do
    if [[ -z "${seen[$pkg]+x}" ]]; then
      uniq_pac+=("$pkg")
      seen["$pkg"]=1
    fi
  done

  seen=()
  local uniq_aur=()
  for pkg in "${aur_pkgs[@]}"; do
    if [[ -z "${seen[$pkg]+x}" ]]; then
      uniq_aur+=("$pkg")
      seen["$pkg"]=1
    fi
  done

  local missing_pac=()
  for pkg in "${uniq_pac[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing_pac+=("$pkg")
  done

  local missing_aur=()
  for pkg in "${uniq_aur[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing_aur+=("$pkg")
  done

  ARCH_PACMAN_PKGS_RESOLVED="${uniq_pac[*]}"
  ARCH_AUR_PKGS_RESOLVED="${uniq_aur[*]}"
  ARCH_PACMAN_PKGS_MISSING="${missing_pac[*]}"
  ARCH_AUR_PKGS_MISSING="${missing_aur[*]}"
}

run_as_target_user() {
  local cmd="$1"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]] && command -v setpriv >/dev/null 2>&1; then
    local uid gid
    uid="$(id -u "$TARGET_USER")"
    gid="$(id -g "$TARGET_USER")"
    env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      setpriv --reuid "$uid" --regid "$gid" --clear-groups bash -lc "$cmd"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "$TARGET_USER" -- bash -lc "$cmd"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" bash -lc "$cmd"
  else
    err "Neither runuser nor sudo found. Cannot execute as $TARGET_USER."
    return 1
  fi
}

run_as_target_user_argv() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]] && command -v setpriv >/dev/null 2>&1; then
    local uid gid
    uid="$(id -u "$TARGET_USER")"
    gid="$(id -g "$TARGET_USER")"
    env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      setpriv --reuid "$uid" --regid "$gid" --clear-groups "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "$TARGET_USER" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" "$@"
  else
    err "Neither runuser nor sudo found. Cannot execute as $TARGET_USER."
    return 1
  fi
}

install_aur_helper() {
  local helper="$1"
  [[ "$helper" == "yay" || "$helper" == "paru" ]] || return 0

  if command -v "$helper" >/dev/null 2>&1; then
    log "$helper already installed. Skipping."
    return 0
  fi

  local build_root="/tmp/${helper}-build-${TS}"
  local repo_url="https://aur.archlinux.org/${helper}.git"

  log "Installing AUR helper: $helper (missing but required)"
  pacman -S --needed --noconfirm base-devel git
  if pacman -Si "$helper" >/dev/null 2>&1; then
    log "Installing AUR helper from pacman repository: $helper"
    pacman -S --needed --noconfirm "$helper"
    return 0
  fi
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$build_root"
  run_as_target_user "rm -rf '$build_root/$helper' && git clone '$repo_url' '$build_root/$helper' && cd '$build_root/$helper' && makepkg -si --noconfirm"
}

install_arch_base_if_selected() {
  [[ "$ARCH_BASE_ENABLE" == "yes" ]] || return 0

  optimize_pacman_mirrors_if_selected
  enable_selected_repositories_if_needed
  enable_chaotic_aur_if_selected
  resolve_arch_plan

  if [[ -n "$ARCH_PACMAN_PKGS_MISSING" ]]; then
    local -a pac_missing_pkgs=()
    # shellcheck disable=SC2206
    pac_missing_pkgs=($ARCH_PACMAN_PKGS_MISSING)
    log "Installing missing pacman packages from Arch base module"
    pacman -S --needed --noconfirm "${pac_missing_pkgs[@]}"
  else
    log "Arch base pacman packages already installed."
  fi

  if [[ -n "$ARCH_AUR_PKGS_MISSING" ]]; then
    local -a aur_missing_pkgs=()
    # shellcheck disable=SC2206
    aur_missing_pkgs=($ARCH_AUR_PKGS_MISSING)
    local helper="$ARCH_AUR_HELPER"
    if [[ "$helper" == "skip" || "$helper" == "s" ]]; then
      if command -v yay >/dev/null 2>&1; then
        helper="yay"
      elif command -v paru >/dev/null 2>&1; then
        helper="paru"
      elif pacman -Si yay >/dev/null 2>&1; then
        helper="yay"
      elif pacman -Si paru >/dev/null 2>&1; then
        helper="paru"
      else
        helper="$(choose_menu 'AUR Packages Are Required; Choose Helper To Continue' \
          'Yay|Install/use yay' \
          'Paru|Install/use paru')"
        helper="${helper,,}"
      fi
    fi

    [[ "$helper" == "s" ]] && helper="skip"
    if [[ "$helper" == "skip" ]]; then
      warn "Skipping AUR package install although some were selected: $ARCH_AUR_PKGS_MISSING"
      return 0
    fi

    command -v "$helper" >/dev/null 2>&1 || install_aur_helper "$helper"
    log "Installing missing AUR packages with $helper"
    run_as_target_user_argv "$helper" -S --noconfirm --needed "${aur_missing_pkgs[@]}"
  fi
}

install_oh_my_zsh_if_selected() {
  [[ "$ARCH_INSTALL_OH_MY_ZSH" == "yes" ]] || return 0
  if ! command -v zsh >/dev/null 2>&1; then
    warn "Skipping Oh My Zsh install because zsh is not installed."
    return 0
  fi
  local target_omz="$TARGET_HOME/.oh-my-zsh"
  if [[ -d "$target_omz" ]]; then
    log "Oh My Zsh already exists for $TARGET_USER. Skipping."
    return 0
  fi
  log "Installing Oh My Zsh for $TARGET_USER"
  run_as_target_user "git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git '$target_omz'" || {
    warn "Oh My Zsh clone failed."
    return 0
  }
  if [[ ! -f "$TARGET_HOME/.zshrc" ]]; then
    run_as_target_user "cp '$target_omz/templates/zshrc.zsh-template' '$TARGET_HOME/.zshrc'" || warn "Failed to create default .zshrc from template."
  fi
}

set_default_shell_if_selected() {
  local shell_bin=""
  case "$ARCH_SHELL_CHOICE" in
    skip)
      log "Skipping default shell change."
      return 0
      ;;
    fish) shell_bin="$(command -v fish || true)" ;;
    oh-my-zsh) shell_bin="$(command -v zsh || true)" ;;
    bash|*) shell_bin="$(command -v bash || true)" ;;
  esac

  if [[ -z "$shell_bin" ]]; then
    warn "Selected shell binary not found for choice: $ARCH_SHELL_CHOICE"
    return 0
  fi

  local current_shell
  current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7 || true)"
  if [[ "$current_shell" == "$shell_bin" ]]; then
    log "Default shell already set for $TARGET_USER: $shell_bin"
    return 0
  fi

  log "Setting default shell for $TARGET_USER -> $shell_bin"
  if [[ -f /etc/shells ]] && ! grep -qxF "$shell_bin" /etc/shells; then
    echo "$shell_bin" >> /etc/shells
  fi
  if ! usermod -s "$shell_bin" "$TARGET_USER"; then
    if command -v chsh >/dev/null 2>&1; then
      chsh -s "$shell_bin" "$TARGET_USER" || {
        warn "Failed to set default shell for $TARGET_USER -> $shell_bin"
        return 0
      }
    else
      warn "Failed to set default shell for $TARGET_USER -> $shell_bin"
      return 0
    fi
  fi
  refresh_user_context
  if [[ "$TARGET_SHELL" != "$shell_bin" ]]; then
    warn "Shell change command ran, but detected shell is still $TARGET_SHELL"
  fi
}

disable_display_managers_for_autologin() {
  local dm="${DETECTED_DM:-none}"
  [[ "$dm" == "none" ]] && { log "No detected display manager to manage."; return 0; }

  if [[ "$AUTOLOGIN_DM_ACTION" == "keep" ]]; then
    log "Keeping display manager unchanged: $dm"
    return 0
  fi

  if systemctl list-unit-files | awk '{print $1}' | grep -qx "${dm}.service"; then
    if systemctl is-enabled "$dm" >/dev/null 2>&1 || systemctl is-active "$dm" >/dev/null 2>&1; then
      log "Disabling display manager: $dm"
      systemctl disable --now "$dm" || true
    fi
  fi

  if [[ "$AUTOLOGIN_DM_ACTION" == "remove" ]]; then
    log "Removing display manager package: $dm"
    pacman -Rns --noconfirm "$dm" || warn "Failed to remove $dm package. You may remove it manually."
  fi
}

dedupe_word_list() {
  local input="$1"
  local -A seen=()
  local out="" w
  for w in $input; do
    if [[ -z "${seen[$w]+x}" ]]; then
      out+=" $w"
      seen["$w"]=1
    fi
  done
  echo "$out" | xargs
}

detect_installed_kernel_header_pkgs() {
  local pkgs=()
  command -v pacman >/dev/null 2>&1 || return 0

  pacman -Q linux >/dev/null 2>&1 && pkgs+=(linux-headers)
  pacman -Q linux-lts >/dev/null 2>&1 && pkgs+=(linux-lts-headers)
  pacman -Q linux-zen >/dev/null 2>&1 && pkgs+=(linux-zen-headers)
  pacman -Q linux-hardened >/dev/null 2>&1 && pkgs+=(linux-hardened-headers)

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    case "$(uname -r 2>/dev/null || true)" in
      *-zen*) pkgs+=(linux-zen-headers) ;;
      *-lts*) pkgs+=(linux-lts-headers) ;;
      *-hardened*) pkgs+=(linux-hardened-headers) ;;
      *) pkgs+=(linux-headers) ;;
    esac
  fi

  printf '%s\n' "$(dedupe_word_list "${pkgs[*]:-}")"
}

driver_requires_dkms_headers() {
  local all_driver_pkgs="${DRIVER_SELECTED_PKGS_PACMAN:-} ${DRIVER_SELECTED_PKGS_AUR:-}"
  [[ "$all_driver_pkgs" == *"-dkms"* ]]
}

driver_collect_detection() {
  local lspci_out="" lsusb_out="" cpu_vendor=""
  if command -v lspci >/dev/null 2>&1; then
    lspci_out="$(lspci -nnk 2>/dev/null || true)"
  fi
  if command -v lsusb >/dev/null 2>&1; then
    lsusb_out="$(lsusb 2>/dev/null || true)"
  fi
  if command -v lscpu >/dev/null 2>&1; then
    cpu_vendor="$(lscpu 2>/dev/null | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
  fi

  DRIVER_GPU_RECO_PKGS=""
  DRIVER_CHIPSET_RECO_PKGS=""
  DRIVER_NETWORK_RECO_PKGS=""
  DRIVER_OTHERS_RECO_PKGS=""
  DRIVER_GPU_MENU_PKGS=""
  DRIVER_CHIPSET_MENU_PKGS=""
  DRIVER_NETWORK_MENU_PKGS=""
  DRIVER_OTHERS_MENU_PKGS=""
  local kernel_header_pkgs=""
  kernel_header_pkgs="$(detect_installed_kernel_header_pkgs)"

  local gpu_lines chipset_lines net_lines other_lines
  gpu_lines="$(echo "$lspci_out" | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)"
  chipset_lines="$(echo "$lspci_out" | grep -Ei 'ISA bridge|SMBus|Host bridge|PCI bridge' || true)"
  net_lines="$(echo "$lspci_out" | grep -Ei 'Ethernet controller|Network controller|Wireless|Bluetooth' || true)"
  other_lines="$(echo "$lspci_out" | grep -Ei 'Audio device|Multimedia controller|RAID bus controller|USB controller' || true)"

  if [[ -n "$gpu_lines" ]]; then
    DRIVER_GPU_DETECTED_TEXT="$(echo "$gpu_lines" | head -n 3 | sed 's/^[[:space:]]*//' | paste -sd '; ' -)"
  else
    DRIVER_GPU_DETECTED_TEXT="No discrete GPU entry detected from lspci."
  fi
  if [[ -n "$chipset_lines" ]]; then
    DRIVER_CHIPSET_DETECTED_TEXT="$(echo "$chipset_lines" | head -n 2 | sed 's/^[[:space:]]*//' | paste -sd '; ' -)"
  else
    DRIVER_CHIPSET_DETECTED_TEXT="No chipset bridge entry detected from lspci."
  fi
  if [[ -n "$net_lines" || -n "$lsusb_out" ]]; then
    DRIVER_NETWORK_DETECTED_TEXT="$( { echo "$net_lines"; echo "$lsusb_out" | grep -Ei 'Bluetooth|802\.11|Wireless' || true; } | sed '/^$/d' | head -n 3 | sed 's/^[[:space:]]*//' | paste -sd '; ' - )"
  else
    DRIVER_NETWORK_DETECTED_TEXT="No network/WLAN/Bluetooth controller entry detected."
  fi
  if [[ -n "$other_lines" ]]; then
    DRIVER_OTHERS_DETECTED_TEXT="$(echo "$other_lines" | head -n 3 | sed 's/^[[:space:]]*//' | paste -sd '; ' -)"
  else
    DRIVER_OTHERS_DETECTED_TEXT="No additional miscellaneous controller entries detected."
  fi

  if echo "$gpu_lines" | grep -qi 'NVIDIA'; then
    DRIVER_GPU_RECO_PKGS+=" nvidia-open-dkms nvidia-utils nvidia-settings ${kernel_header_pkgs}"
    [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && DRIVER_GPU_RECO_PKGS+=" lib32-nvidia-utils"
    DRIVER_GPU_MENU_PKGS+=" nvidia-open-dkms nvidia-open nvidia-dkms nvidia nvidia-utils nvidia-settings ${kernel_header_pkgs}"
    [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && DRIVER_GPU_MENU_PKGS+=" lib32-nvidia-utils"
  fi
  if echo "$gpu_lines" | grep -qiE 'AMD|Advanced Micro Devices|Radeon'; then
    DRIVER_GPU_RECO_PKGS+=" mesa vulkan-radeon xf86-video-amdgpu"
    [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && DRIVER_GPU_RECO_PKGS+=" lib32-vulkan-radeon"
    DRIVER_GPU_MENU_PKGS+=" mesa vulkan-radeon xf86-video-amdgpu"
    [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && DRIVER_GPU_MENU_PKGS+=" lib32-vulkan-radeon"
  fi
  if echo "$gpu_lines" | grep -qiE 'Intel'; then
    DRIVER_GPU_RECO_PKGS+=" mesa vulkan-intel intel-media-driver"
    [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && DRIVER_GPU_RECO_PKGS+=" lib32-vulkan-intel"
    DRIVER_GPU_MENU_PKGS+=" mesa vulkan-intel intel-media-driver"
    [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && DRIVER_GPU_MENU_PKGS+=" lib32-vulkan-intel"
  fi
  if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
    DRIVER_CHIPSET_RECO_PKGS+=" intel-ucode"
  elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
    DRIVER_CHIPSET_RECO_PKGS+=" amd-ucode"
  fi
  if [[ -n "$chipset_lines" || -n "$cpu_vendor" ]]; then
    DRIVER_CHIPSET_RECO_PKGS+=" fwupd"
  fi
  DRIVER_CHIPSET_MENU_PKGS="$DRIVER_CHIPSET_RECO_PKGS"

  if echo "$net_lines" | grep -qiE 'Network controller|Wireless'; then
    DRIVER_NETWORK_RECO_PKGS+=" networkmanager iwd wpa_supplicant"
  fi
  if echo "$net_lines" | grep -qi 'Ethernet'; then
    DRIVER_NETWORK_RECO_PKGS+=" networkmanager"
  fi
  if echo "$net_lines $lsusb_out" | grep -qi 'Bluetooth'; then
    DRIVER_NETWORK_RECO_PKGS+=" bluez bluez-utils"
  fi
  if echo "$net_lines" | grep -qi 'Broadcom'; then
    DRIVER_NETWORK_RECO_PKGS+=" broadcom-wl-dkms ${kernel_header_pkgs}"
  fi
  DRIVER_NETWORK_MENU_PKGS="$DRIVER_NETWORK_RECO_PKGS"

  DRIVER_OTHERS_RECO_PKGS+=" linux-firmware"
  if echo "$other_lines" | grep -qiE 'Audio|Multimedia'; then
    DRIVER_OTHERS_RECO_PKGS+=" sof-firmware"
  fi
  DRIVER_OTHERS_MENU_PKGS="$DRIVER_OTHERS_RECO_PKGS"

  DRIVER_GPU_RECO_PKGS="$(echo "$DRIVER_GPU_RECO_PKGS" | xargs)"
  DRIVER_CHIPSET_RECO_PKGS="$(echo "$DRIVER_CHIPSET_RECO_PKGS" | xargs)"
  DRIVER_NETWORK_RECO_PKGS="$(echo "$DRIVER_NETWORK_RECO_PKGS" | xargs)"
  DRIVER_OTHERS_RECO_PKGS="$(echo "$DRIVER_OTHERS_RECO_PKGS" | xargs)"
  DRIVER_GPU_MENU_PKGS="$(dedupe_word_list "$DRIVER_GPU_MENU_PKGS")"
  DRIVER_CHIPSET_MENU_PKGS="$(dedupe_word_list "$DRIVER_CHIPSET_MENU_PKGS")"
  DRIVER_NETWORK_MENU_PKGS="$(dedupe_word_list "$DRIVER_NETWORK_MENU_PKGS")"
  DRIVER_OTHERS_MENU_PKGS="$(dedupe_word_list "$DRIVER_OTHERS_MENU_PKGS")"
}

install_driver_configuration_if_selected() {
  [[ "$DRIVER_CONFIG_MODE" != "skip" ]] || return 0

  if driver_requires_dkms_headers; then
    local detected_header_pkgs=""
    detected_header_pkgs="$(detect_installed_kernel_header_pkgs)"
    if [[ -n "$detected_header_pkgs" ]]; then
      DRIVER_SELECTED_PKGS_PACMAN="$(dedupe_word_list "${DRIVER_SELECTED_PKGS_PACMAN:-} ${detected_header_pkgs}")"
    fi
  fi

  if [[ -n "$DRIVER_SELECTED_PKGS_PACMAN" ]]; then
    local -a driver_pac_pkgs=()
    # shellcheck disable=SC2206
    driver_pac_pkgs=($DRIVER_SELECTED_PKGS_PACMAN)
    log "Installing selected driver packages (pacman)"
    pacman -S --needed --noconfirm "${driver_pac_pkgs[@]}"
  else
    warn "Driver configuration selected, but no pacman driver package queued."
  fi

  if [[ -n "$DRIVER_SELECTED_PKGS_AUR" ]]; then
    local -a driver_aur_pkgs=()
    # shellcheck disable=SC2206
    driver_aur_pkgs=($DRIVER_SELECTED_PKGS_AUR)
    local helper="$ARCH_AUR_HELPER"
    if [[ "$helper" == "skip" || "$helper" == "s" ]]; then
      if command -v yay >/dev/null 2>&1; then
        helper="yay"
      elif command -v paru >/dev/null 2>&1; then
        helper="paru"
      elif pacman -Si yay >/dev/null 2>&1; then
        helper="yay"
      elif pacman -Si paru >/dev/null 2>&1; then
        helper="paru"
      fi
    fi
    if [[ -n "$helper" && "$helper" != "skip" ]]; then
      command -v "$helper" >/dev/null 2>&1 || install_aur_helper "$helper"
      run_as_target_user_argv "$helper" -S --noconfirm --needed "${driver_aur_pkgs[@]}"
    else
      warn "AUR driver packages selected but no AUR helper available: $DRIVER_SELECTED_PKGS_AUR"
    fi
  fi

  if driver_requires_dkms_headers && command -v dkms >/dev/null 2>&1; then
    log "Rebuilding DKMS modules for installed kernels"
    dkms autoinstall || warn "DKMS autoinstall failed. Check matching kernel header packages and run 'dkms autoinstall' manually."
  fi

  if list_has "${DRIVER_SELECTED_PKGS_PACMAN:-}" "nvidia" || \
     list_has "${DRIVER_SELECTED_PKGS_PACMAN:-}" "nvidia-dkms" || \
     list_has "${DRIVER_SELECTED_PKGS_PACMAN:-}" "nvidia-open" || \
     list_has "${DRIVER_SELECTED_PKGS_PACMAN:-}" "nvidia-open-dkms"; then
    command -v modprobe >/dev/null 2>&1 && modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm 2>/dev/null || \
      warn "NVIDIA kernel modules could not be loaded immediately. A reboot may still be required."
  fi
}

resolve_auth_agent_pkg() {
  if [[ "$AUTH_AGENT_CHOICE" == "none" ]]; then
    echo ""
    return
  fi
  if [[ "$AUTH_AGENT_CHOICE" != "auto" ]]; then
    echo "$AUTH_AGENT_CHOICE"
    return
  fi

  case "$SESSION_CHOICE" in
    plasma) echo "" ;;
    gnome) echo "" ;;
    lxqt) echo "lxqt-policykit" ;;
    mate) echo "mate-polkit" ;;
    xfce) echo "xfce-polkit" ;;
    hyprland|sway|river|wayfire|labwc|niri|i3|bspwm|awesome|openbox|custom) echo "polkit-gnome" ;;
    *) echo "polkit-gnome" ;;
  esac
}

resolve_auth_agent_start_cmd() {
  local pkg="$1"
  case "$pkg" in
    polkit-gnome)
      [[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]] && echo "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" || echo ""
      ;;
    mate-polkit)
      [[ -x /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 ]] && echo "/usr/lib/mate-polkit/polkit-mate-authentication-agent-1" || echo ""
      ;;
    lxqt-policykit)
      [[ -x /usr/bin/lxqt-policykit-agent ]] && echo "/usr/bin/lxqt-policykit-agent" || echo ""
      ;;
    xfce-polkit)
      if [[ -x /usr/lib/xfce-polkit/xfce-polkit ]]; then
        echo "/usr/lib/xfce-polkit/xfce-polkit"
      elif [[ -x /usr/bin/xfce-polkit ]]; then
        echo "/usr/bin/xfce-polkit"
      else
        echo ""
      fi
      ;;
    *)
      echo ""
      ;;
  esac
}

get_autostart_command() {
  case "$SESSION_CHOICE" in
    hyprland)
      if [[ -x /usr/bin/start-hyprland ]]; then
        echo "/usr/bin/start-hyprland"
      elif [[ -x /usr/bin/Hyprland ]]; then
        echo "/usr/bin/Hyprland"
      else
        echo "Hyprland"
      fi
      ;;
    plasma)
      if [[ -x /usr/bin/startplasma-wayland ]]; then
        echo "/usr/bin/startplasma-wayland"
      elif [[ -x /usr/bin/startplasma-x11 ]]; then
        echo "/usr/bin/startplasma-x11"
      else
        echo "startplasma-wayland"
      fi
      ;;
    gnome) echo "gnome-session" ;;
    xfce) echo "startxfce4" ;;
    sway) echo "sway" ;;
    river) echo "river" ;;
    wayfire) echo "wayfire" ;;
    labwc) echo "labwc" ;;
    niri)
      if [[ -x /usr/bin/niri-session ]]; then
        echo "/usr/bin/niri-session"
      else
        echo "niri"
      fi
      ;;
    cinnamon) echo "cinnamon-session" ;;
    mate) echo "mate-session" ;;
    lxqt) echo "startlxqt" ;;
    budgie) echo "budgie-desktop" ;;
    deepin) echo "startdde" ;;
    pantheon)
      if [[ -x /usr/bin/pantheon-session ]]; then
        echo "/usr/bin/pantheon-session"
      else
        echo "gnome-session --session=pantheon"
      fi
      ;;
    i3) echo "i3" ;;
    bspwm) echo "bspwm" ;;
    awesome) echo "awesome" ;;
    openbox) echo "openbox-session" ;;
    custom) echo "$CUSTOM_AUTOSTART_CMD" ;;
    *) echo "" ;;
  esac
}

install_missing_autostart_session_if_selected() {
  [[ "$AUTOSTART_ENABLE" == "yes" ]] || return 0
  [[ "$AUTOSTART_INSTALL_MISSING_SESSION" == "yes" ]] || return 0
  [[ "$SESSION_CHOICE" != "custom" ]] || return 0

  local pkgs
  pkgs="$(de_packages "$SESSION_CHOICE" "$AUTOSTART_SESSION_INSTALL_PROFILE")"
  if [[ -n "$pkgs" ]]; then
    local -a session_pkgs=()
    # shellcheck disable=SC2206
    session_pkgs=($pkgs)
    log "Installing selected autostart session packages for: $SESSION_CHOICE"
    pacman -S --needed --noconfirm "${session_pkgs[@]}"
  fi
}

install_selected_dewm_packages() {
  [[ -n "${DEWM_SELECTED:-}" ]] || return 0
  local all=() s p
  for s in $DEWM_SELECTED; do
    for p in $(de_packages "$s" "$DEWM_INSTALL_MODE"); do
      [[ -n "$p" ]] && all+=("$p")
    done
  done
  local -A seen=()
  local uniq=()
  for p in "${all[@]}"; do
    if [[ -z "${seen[$p]+x}" ]]; then
      uniq+=("$p")
      seen["$p"]=1
    fi
  done
  if (( ${#uniq[@]} > 0 )); then
    log "Installing selected DE/WM packages ($DEWM_INSTALL_MODE)"
    pacman -S --needed --noconfirm "${uniq[@]}"
  fi
}

ensure_display_manager_selected() {
  [[ "$LOGIN_METHOD" == "display-manager" ]] || return 0
  if [[ "$DISPLAY_MANAGER_CHOICE" == "none" ]]; then
    local inferred="none"
    local first_sel
    first_sel="$(echo "$DEWM_SELECTED" | awk '{print $1}')"
    [[ -n "$first_sel" ]] && inferred="$(default_dm_for_session "$first_sel")"
    if [[ "$inferred" != "none" ]]; then
      DISPLAY_MANAGER_CHOICE="$inferred"
      log "No explicit DM selected; using inferred default DM: $DISPLAY_MANAGER_CHOICE"
    else
      warn "No display manager selected/inferred. Skipping DM install."
      return 0
    fi
  fi
  log "Ensuring display manager is installed/enabled: $DISPLAY_MANAGER_CHOICE"
  pacman -S --needed --noconfirm "$DISPLAY_MANAGER_CHOICE" || true

  local dm
  for dm in gdm sddm lightdm ly; do
    if [[ "$dm" == "$DISPLAY_MANAGER_CHOICE" ]]; then
      systemctl enable "$dm" || true
      systemctl start "$dm" || true
    else
      systemctl disable --now "$dm" >/dev/null 2>&1 || true
    fi
  done
}

apply_manual_login_mode() {
  [[ "$LOGIN_METHOD" == "manual" ]] || return 0
  local dropin="/etc/systemd/system/getty@${TTY_DEVICE}.service.d/autologin.conf"
  rm -f "$dropin" >/dev/null 2>&1 || true
  rmdir --ignore-fail-on-non-empty "/etc/systemd/system/getty@${TTY_DEVICE}.service.d" >/dev/null 2>&1 || true
  local dm
  for dm in gdm sddm lightdm ly; do
    systemctl disable --now "$dm" >/dev/null 2>&1 || true
    pacman -Q "$dm" >/dev/null 2>&1 && pacman -Rns --noconfirm "$dm" >/dev/null 2>&1 || true
  done
  remove_autostart_block "$SHELL_RC_FILE"
}

remove_autostart_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

inject_autostart_block() {
  local cmd="$1"
  local auth_agent_cmd="${2:-}"
  local shell_base
  shell_base="$(basename "$TARGET_SHELL")"

  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$(dirname "$SHELL_RC_FILE")"
  [[ -f "$SHELL_RC_FILE" ]] || install -m 0644 -o "$TARGET_USER" -g "$TARGET_USER" /dev/null "$SHELL_RC_FILE"

  remove_autostart_block "$SHELL_RC_FILE"

  {
    echo "$MARK_START"
    if [[ "$shell_base" == "fish" ]]; then
      cat <<EOT
if test (tty) = "/dev/${TTY_DEVICE}"; and test -z "\$DISPLAY"; and test -z "\$WAYLAND_DISPLAY"
    if test -n "${auth_agent_cmd}"; and test -x "${auth_agent_cmd}"
        if command -sq pgrep
            if not pgrep -u (id -u) -f (basename "${auth_agent_cmd}") >/dev/null 2>&1
                ${auth_agent_cmd} >/dev/null 2>&1 &
            end
        else
            ${auth_agent_cmd} >/dev/null 2>&1 &
        end
    end
    exec ${cmd}
end
EOT
    else
      cat <<EOT
if [ "\$(tty)" = "/dev/${TTY_DEVICE}" ] && [ -z "\$DISPLAY" ] && [ -z "\$WAYLAND_DISPLAY" ]; then
  if [ -n "${auth_agent_cmd}" ] && [ -x "${auth_agent_cmd}" ]; then
    if command -v pgrep >/dev/null 2>&1; then
      if ! pgrep -u "\$(id -u)" -f "$(basename "${auth_agent_cmd}")" >/dev/null 2>&1; then
        ${auth_agent_cmd} >/dev/null 2>&1 &
      fi
    else
      ${auth_agent_cmd} >/dev/null 2>&1 &
    fi
  fi
  exec ${cmd}
fi
EOT
    fi
    echo "$MARK_END"
  } >> "$SHELL_RC_FILE"

  chown "$TARGET_USER:$TARGET_USER" "$SHELL_RC_FILE"
}

configure_tty_autologin() {
  local dropin_dir="/etc/systemd/system/getty@${TTY_DEVICE}.service.d"
  install -d -m 0755 "$dropin_dir"
  cat > "$dropin_dir/autologin.conf" <<EOT
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin ${TARGET_USER} --noclear %I \$TERM
EOT

  systemctl daemon-reload
  systemctl enable "getty@${TTY_DEVICE}.service"
  loginctl enable-linger "$TARGET_USER"
}

detect_grub_mkconfig_cmd() {
  if command -v grub-mkconfig >/dev/null 2>&1; then
    echo "grub-mkconfig"
  elif command -v grub2-mkconfig >/dev/null 2>&1; then
    echo "grub2-mkconfig"
  else
    echo ""
  fi
}

detect_grub_cfg_path() {
  local path=""
  if [[ -f /boot/grub/grub.cfg || -d /boot/grub ]]; then
    path="/boot/grub/grub.cfg"
  elif [[ -f /boot/grub2/grub.cfg || -d /boot/grub2 ]]; then
    path="/boot/grub2/grub.cfg"
  elif [[ -d /boot ]]; then
    path="/boot/grub/grub.cfg"
  fi
  echo "$path"
}

gpu_has_explicit_selection() {
  [[ -n "${DRIVER_SELECTED_PKGS_PACMAN:-}" || -n "${DRIVER_SELECTED_PKGS_AUR:-}" ]]
}

gpu_pkg_selected_or_installed() {
  local pkg="${1:-}"
  [[ -n "$pkg" ]] || return 1
  list_has "${DRIVER_SELECTED_PKGS_PACMAN:-}" "$pkg" && return 0
  if gpu_has_explicit_selection; then
    return 1
  fi
  command -v pacman >/dev/null 2>&1 && pacman -Q "$pkg" >/dev/null 2>&1 && return 0
  return 1
}

gpu_detect_boot_modules() {
  local modules=() gpu_lines=""
  if command -v lspci >/dev/null 2>&1; then
    gpu_lines="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
  fi

  if gpu_pkg_selected_or_installed nvidia-open-dkms || gpu_pkg_selected_or_installed nvidia-open || \
     gpu_pkg_selected_or_installed nvidia-dkms || gpu_pkg_selected_or_installed nvidia || \
     gpu_pkg_selected_or_installed nvidia-utils || \
     (! gpu_has_explicit_selection && echo "$gpu_lines" | grep -qi 'NVIDIA'); then
    modules+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
  fi

  if gpu_pkg_selected_or_installed xf86-video-amdgpu || gpu_pkg_selected_or_installed vulkan-radeon || \
     gpu_pkg_selected_or_installed lib32-vulkan-radeon || \
     (! gpu_has_explicit_selection && echo "$gpu_lines" | grep -qiE 'AMD|Advanced Micro Devices|Radeon'); then
    modules+=(amdgpu)
  fi

  if gpu_pkg_selected_or_installed vulkan-intel || gpu_pkg_selected_or_installed lib32-vulkan-intel || \
     gpu_pkg_selected_or_installed intel-media-driver || \
     (! gpu_has_explicit_selection && echo "$gpu_lines" | grep -qi 'Intel'); then
    modules+=(i915)
  fi

  printf '%s\n' "$(dedupe_word_list "${modules[*]:-}")"
}

configure_gpu_boot_support() {
  local grub_file="/etc/default/grub"
  local mkinit_file="/etc/mkinitcpio.conf"
  local gpu_modules current_modules changed_mkinit="no" changed_grub="no" current_default

  [[ -f "$mkinit_file" ]] || return 0

  gpu_modules="$(gpu_detect_boot_modules)"
  [[ -n "$gpu_modules" ]] || return 0

  if grep -q '^MODULES=' "$mkinit_file"; then
    current_modules="$(sed -n 's/^MODULES=(\(.*\))$/\1/p' "$mkinit_file" | head -n1)"
    current_modules="$(dedupe_word_list "$current_modules $gpu_modules")"
    sed -i "s|^MODULES=(.*)|MODULES=(${current_modules})|" "$mkinit_file"
    changed_mkinit="yes"
  else
    printf 'MODULES=(%s)\n' "$gpu_modules" >> "$mkinit_file"
    changed_mkinit="yes"
  fi

  if grep -q '^HOOKS=' "$mkinit_file" && ! grep -Eq '^HOOKS=.*\bkms\b' "$mkinit_file"; then
    sed -i '/^HOOKS=/ s/\(HOOKS=(.*\) keyboard/\1 kms keyboard/' "$mkinit_file"
    if ! grep -Eq '^HOOKS=.*\bkms\b' "$mkinit_file"; then
      sed -i '/^HOOKS=/ s/^)$/ kms)/' "$mkinit_file"
    fi
    changed_mkinit="yes"
  fi

  if [[ -f "$grub_file" ]] && list_has "$gpu_modules" "nvidia_drm"; then
    current_default="$(sed -n "s/^GRUB_CMDLINE_LINUX_DEFAULT='\(.*\)'/\1/p" "$grub_file")"
    if [[ -z "$current_default" ]]; then
      current_default="$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' "$grub_file")"
    fi
    current_default=" $(echo "${current_default:-}" | tr -s ' ') "
    if [[ "$current_default" != *" nvidia_drm.modeset=1 "* ]]; then
      current_default+="nvidia_drm.modeset=1 "
      current_default="$(echo "$current_default" | xargs)"
      if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'|" "$grub_file"
      else
        echo "GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'" >> "$grub_file"
      fi
      changed_grub="yes"
    fi
  fi

  if [[ "$changed_mkinit" == "yes" ]]; then
    log "Applied GPU-aware initramfs support: ${gpu_modules}"
    if command -v mkinitcpio >/dev/null 2>&1; then
      mkinitcpio -P || warn "mkinitcpio failed after GPU boot support changes. Continue with caution and regenerate manually."
    fi
  fi

  if [[ "$changed_grub" == "yes" ]]; then
    log "Applied NVIDIA DRM boot parameter for smoother early modesetting."
    regenerate_bootloader_config || true
  fi
}

regenerate_bootloader_config() {
  local grub_cmd grub_cfg
  grub_cmd="$(detect_grub_mkconfig_cmd)"
  grub_cfg="$(detect_grub_cfg_path)"

  if [[ -z "$grub_cmd" ]]; then
    warn "GRUB config generation skipped: neither grub-mkconfig nor grub2-mkconfig was found."
    return 0
  fi
  if [[ -z "$grub_cfg" ]]; then
    warn "GRUB config generation skipped: unable to determine grub.cfg output path."
    return 0
  fi

  local grub_dir
  grub_dir="$(dirname "$grub_cfg")"
  if [[ ! -d "$grub_dir" ]]; then
    warn "GRUB target directory missing ($grub_dir). Creating it now."
    if ! mkdir -p "$grub_dir"; then
      warn "Failed to create GRUB target directory: $grub_dir"
      warn "Please verify /boot mount and filesystem permissions, then retry."
      return 0
    fi
  fi

  if command -v findmnt >/dev/null 2>&1; then
    if ! findmnt -rn -T /boot >/dev/null 2>&1; then
      warn "/boot does not appear to be a mounted filesystem. Proceeding anyway."
      warn "If this is not intended, mount /boot and regenerate GRUB config again."
    fi
  fi

  if ! "$grub_cmd" -o "$grub_cfg"; then
    warn "Failed to generate GRUB config via '$grub_cmd -o $grub_cfg'."
    warn "Please verify GRUB install state and /boot mount, then run manually."
    return 0
  fi
  log "GRUB config generated: $grub_cfg"

  if [[ "$BOOT_OS_PROBER" == "yes" ]]; then
    if ! grep -qiE 'windows|microsoft' "$grub_cfg" 2>/dev/null; then
      warn "GRUB config generated, but no Windows entry was found in $grub_cfg."
      warn "If Windows exists, verify: Fast Startup disabled, BitLocker state, and matching UEFI/Legacy install mode."
    fi
  fi
}

configure_boot_tuning() {
  local grub_file="/etc/default/grub"
  local mkinit_file="/etc/mkinitcpio.conf"

  if [[ ! -f "$grub_file" || ! -f "$mkinit_file" ]]; then
    warn "Skipping boot tuning: missing $grub_file or $mkinit_file"
    return
  fi

  local current_default
  current_default="$(sed -n "s/^GRUB_CMDLINE_LINUX_DEFAULT='\(.*\)'/\1/p" "$grub_file")"
  if [[ -z "$current_default" ]]; then
    current_default="$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' "$grub_file")"
  fi

  local normalized_default
  normalized_default=" $(echo "$current_default" | tr -s ' ') "

  if [[ "$BOOT_SILENT" == "yes" ]]; then
    if [[ -z "$current_default" ]]; then
      current_default="quiet loglevel=3 udev.log_priority=3 rd.udev.log_priority=3 vt.global_cursor_default=0"
    else
      current_default="$normalized_default"
      for arg in quiet loglevel=3 udev.log_priority=3 rd.udev.log_priority=3 vt.global_cursor_default=0; do
        [[ "$current_default" == *" $arg "* ]] || current_default+="$arg "
      done
      current_default="$(echo "$current_default" | xargs)"
    fi
    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
      sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'|" "$grub_file"
    else
      echo "GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'" >> "$grub_file"
    fi
  fi

  if [[ "$BOOT_OS_PROBER" == "yes" ]]; then
    if grep -qE '^#?GRUB_DISABLE_OS_PROBER=' "$grub_file"; then
      sed -i 's|^#\?GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|' "$grub_file"
    else
      echo 'GRUB_DISABLE_OS_PROBER=false' >> "$grub_file"
    fi
  fi

  if [[ "$BOOT_PLYMOUTH_ACTION" == "disable" ]]; then
    if [[ -f "$grub_file" ]]; then
      current_default=" $(sed -n "s/^GRUB_CMDLINE_LINUX_DEFAULT='\(.*\)'/\1/p" "$grub_file") "
      if [[ "$current_default" == "  " ]]; then
        current_default=" $(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' "$grub_file") "
      fi
      current_default="${current_default// splash / }"
      current_default="$(echo "$current_default" | xargs)"
      if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'|" "$grub_file"
      else
        echo "GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'" >> "$grub_file"
      fi
    fi
    if grep -q '^HOOKS=' "$mkinit_file"; then
      sed -i '/^HOOKS=/ s/ plymouth / /g; /^HOOKS=/ s/(plymouth /( /; /^HOOKS=/ s/ plymouth)/)/; /^HOOKS=/ s/[[:space:]]\+/ /g' "$mkinit_file"
    fi
    systemctl disable --now plymouth-start.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true
    systemctl mask plymouth-start.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true
  elif [[ "$BOOT_PLYMOUTH_ACTION" == "enable" ]]; then
    pacman -S --needed --noconfirm plymouth || true
    if [[ -f "$grub_file" ]]; then
      current_default=" $(sed -n "s/^GRUB_CMDLINE_LINUX_DEFAULT='\(.*\)'/\1/p" "$grub_file") "
      if [[ "$current_default" == "  " ]]; then
        current_default=" $(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' "$grub_file") "
      fi
      [[ "$current_default" == *" splash "* ]] || current_default+="splash "
      current_default="$(echo "$current_default" | xargs)"
      if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'|" "$grub_file"
      else
        echo "GRUB_CMDLINE_LINUX_DEFAULT='${current_default}'" >> "$grub_file"
      fi
    fi
    if grep -q '^HOOKS=' "$mkinit_file"; then
      if ! grep -Eq '^HOOKS=.*\bplymouth\b' "$mkinit_file"; then
        sed -i '/^HOOKS=/ s/\(HOOKS=(.*\) filesystems/\1 plymouth filesystems/' "$mkinit_file"
      fi
    fi
    systemctl unmask plymouth-start.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true
    systemctl enable plymouth-start.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true
  else
    log "Plymouth action set to Skip; leaving current Plymouth integration untouched."
  fi

  if ask_yes_no 'Regenerate initramfs + grub config now?' 'y'; then
    if command -v mkinitcpio >/dev/null 2>&1; then
      mkinitcpio -P || warn "mkinitcpio failed. Continue with caution and regenerate manually."
    else
      warn "mkinitcpio not found; skipping initramfs regeneration."
    fi
    if [[ "$BOOT_OS_PROBER" == "yes" ]]; then
      if ensure_os_prober_installed; then
        ensure_os_prober_prereqs || true
        run_os_prober_with_diagnostics || true
      else
        warn "Skipping OS detection scan because os-prober is unavailable."
      fi
    fi
    regenerate_bootloader_config
  else
    warn 'Skipped grub/mkinit regeneration. Run manually later.'
  fi
}

create_backup_snapshot() {
  mkdir -p "$BACKUP_ROOT"
  local bdir="$BACKUP_ROOT/$TS"
  mkdir -p "$bdir"

  local files=()
  [[ -f /etc/default/grub ]] && files+=(/etc/default/grub)
  [[ -f /etc/mkinitcpio.conf ]] && files+=(/etc/mkinitcpio.conf)
  [[ -f "$SHELL_RC_FILE" ]] && files+=("$SHELL_RC_FILE")
  [[ -d "/etc/systemd/system/getty@${TTY_DEVICE}.service.d" ]] && files+=("/etc/systemd/system/getty@${TTY_DEVICE}.service.d")
  [[ -f "$TARGET_HOME/.config/systemd/user/hyprland.service" ]] && files+=("$TARGET_HOME/.config/systemd/user/hyprland.service")

  if (( ${#files[@]} > 0 )); then
    if ! tar -cpf "$bdir/state-before.tar" "${files[@]}" 2>/dev/null; then
      err "Failed to create backup archive: $bdir/state-before.tar"
      exit 1
    fi
  else
    if ! tar -cpf "$bdir/state-before.tar" -T /dev/null 2>/dev/null; then
      err "Failed to create empty backup archive: $bdir/state-before.tar"
      exit 1
    fi
  fi

  cat > "$bdir/meta.env" <<EOM
TS=$TS
TARGET_USER=$TARGET_USER
TARGET_HOME=$TARGET_HOME
TARGET_SHELL=$TARGET_SHELL
SHELL_RC_FILE=$SHELL_RC_FILE
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
AUTOSTART_ENABLE=$AUTOSTART_ENABLE
SESSION_CHOICE=$SESSION_CHOICE
CUSTOM_AUTOSTART_CMD="$CUSTOM_AUTOSTART_CMD"
AUTOSTART_INSTALL_MISSING_SESSION=$AUTOSTART_INSTALL_MISSING_SESSION
AUTOSTART_SESSION_INSTALL_PROFILE=$AUTOSTART_SESSION_INSTALL_PROFILE
BOOT_TUNE_ENABLE=$BOOT_TUNE_ENABLE
BOOT_SILENT=$BOOT_SILENT
BOOT_OS_PROBER=$BOOT_OS_PROBER
BOOT_PLYMOUTH_ACTION=$BOOT_PLYMOUTH_ACTION
BOOTLOADER_ACTION=$BOOTLOADER_ACTION
BOOTLOADER_REPLACE=$BOOTLOADER_REPLACE
BOOTLOADER_CHOICE=$BOOTLOADER_CHOICE
DRIVER_CONFIG_MODE=$DRIVER_CONFIG_MODE
DRIVER_SELECTED_GROUPS="$DRIVER_SELECTED_GROUPS"
DRIVER_SELECTED_PKGS_PACMAN="$DRIVER_SELECTED_PKGS_PACMAN"
DRIVER_SELECTED_PKGS_AUR="$DRIVER_SELECTED_PKGS_AUR"
EOM

  log "Backup snapshot created: $bdir"
}

precheck_distro() {
  if [[ "$MODE" != "install" ]]; then
    return
  fi

  if [[ ! -f /etc/os-release ]]; then
    err "/etc/os-release missing. Unsupported system."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  local id_like="${ID_LIKE:-}"
  local id="${ID:-}"

  if [[ "$id" != "arch" && "$id_like" != *"arch"* ]] && ! command -v pacman >/dev/null 2>&1; then
    err "This script currently supports Arch-based distros only. Detected: $id"
    exit 1
  fi
}

tui_normalize_state() {
  ARCH_SELECTED_CATEGORIES="$(dedupe_word_list "${ARCH_SELECTED_CATEGORIES:-}")"
  ARCH_SELECTED_IDES="$(dedupe_word_list "${ARCH_SELECTED_IDES:-}")"
  ARCH_SELECTED_APPS="$(dedupe_word_list "${ARCH_SELECTED_APPS:-}")"
  ARCH_CUSTOM_APP_PKGS="$(dedupe_word_list "${ARCH_CUSTOM_APP_PKGS:-}")"
  DEWM_SELECTED="$(dedupe_word_list "${DEWM_SELECTED:-}")"
  DRIVER_SELECTED_GROUPS="$(dedupe_word_list "${DRIVER_SELECTED_GROUPS:-}")"
  DRIVER_SELECTED_PKGS_PACMAN="$(dedupe_word_list "${DRIVER_SELECTED_PKGS_PACMAN:-}")"
  DRIVER_SELECTED_PKGS_AUR="$(dedupe_word_list "${DRIVER_SELECTED_PKGS_AUR:-}")"

  if [[ "$ARCH_BASE_ENABLE" == "yes" && -z "$ARCH_SELECTED_CATEGORIES" ]]; then
    ARCH_SELECTED_CATEGORIES="core-system cli-utils"
  fi
  if [[ -n "$ARCH_SELECTED_IDES" ]] && ! list_has "$ARCH_SELECTED_CATEGORIES" "dev-toolchain"; then
    ARCH_SELECTED_CATEGORIES="$(dedupe_word_list "$ARCH_SELECTED_CATEGORIES dev-toolchain")"
  fi

  case "${ARCH_SHELL_CHOICE:-bash}" in
    fish)
      ARCH_INSTALL_FISH="yes"
      ARCH_INSTALL_ZSH="no"
      ARCH_INSTALL_OH_MY_ZSH="no"
      ;;
    oh-my-zsh)
      ARCH_INSTALL_FISH="no"
      ARCH_INSTALL_ZSH="yes"
      ARCH_INSTALL_OH_MY_ZSH="yes"
      ;;
    skip)
      ARCH_INSTALL_FISH="no"
      ARCH_INSTALL_ZSH="no"
      ARCH_INSTALL_OH_MY_ZSH="no"
      ;;
    bash|*)
      ARCH_SHELL_CHOICE="bash"
      ARCH_INSTALL_FISH="no"
      ARCH_INSTALL_ZSH="no"
      ARCH_INSTALL_OH_MY_ZSH="no"
      ;;
  esac

  case "${LOGIN_METHOD:-tty-autologin}" in
    display-manager)
      AUTOSTART_ENABLE="no"
      AUTOLOGIN_DM_ACTION="keep"
      if [[ -z "${DISPLAY_MANAGER_CHOICE:-}" || "$DISPLAY_MANAGER_CHOICE" == "none" ]]; then
        local inferred="none"
        if [[ -n "${DEWM_SELECTED:-}" ]]; then
          inferred="$(default_dm_for_session "$(awk '{print $1}' <<< "$DEWM_SELECTED")")"
        elif [[ "${ARCH_SELECTED_DE:-none}" != "none" ]]; then
          inferred="$(default_dm_for_session "$ARCH_SELECTED_DE")"
        fi
        DISPLAY_MANAGER_CHOICE="$inferred"
      fi
      ;;
    tty-autologin)
      AUTOLOGIN_ENABLE="yes"
      DISPLAY_MANAGER_CHOICE="none"
      [[ -n "${TTY_DEVICE:-}" ]] || TTY_DEVICE="tty1"
      [[ -n "${SESSION_CHOICE:-}" ]] || SESSION_CHOICE="hyprland"
      ;;
    manual)
      DISPLAY_MANAGER_CHOICE="none"
      AUTOLOGIN_ENABLE="no"
      AUTOSTART_ENABLE="no"
      AUTOLOGIN_DM_ACTION="remove"
      ;;
    *)
      LOGIN_METHOD="tty-autologin"
      DISPLAY_MANAGER_CHOICE="none"
      ;;
  esac

  if [[ "$AUTOSTART_ENABLE" != "yes" ]]; then
    AUTOSTART_INSTALL_MISSING_SESSION="no"
  elif [[ "$SESSION_CHOICE" == "custom" && -z "${CUSTOM_AUTOSTART_CMD:-}" ]]; then
    AUTOSTART_ENABLE="no"
    AUTOSTART_INSTALL_MISSING_SESSION="no"
  fi

  case "${BOOTLOADER_ACTION:-keep}" in
    replace)
      BOOTLOADER_REPLACE="yes"
      ;;
    keep|fix)
      BOOTLOADER_REPLACE="no"
      ;;
    *)
      BOOTLOADER_ACTION="keep"
      BOOTLOADER_REPLACE="no"
      ;;
  esac

  if [[ "$DRIVER_CONFIG_MODE" == "skip" ]]; then
    DRIVER_SELECTED_GROUPS=""
    DRIVER_SELECTED_PKGS_PACMAN=""
    DRIVER_SELECTED_PKGS_AUR=""
  elif [[ "$DRIVER_CONFIG_MODE" == "auto" && -z "$DRIVER_SELECTED_PKGS_PACMAN$DRIVER_SELECTED_PKGS_AUR" ]]; then
    driver_collect_detection
    DRIVER_SELECTED_GROUPS=""
    [[ -n "$DRIVER_GPU_RECO_PKGS" ]] && DRIVER_SELECTED_GROUPS="$(dedupe_word_list "$DRIVER_SELECTED_GROUPS gpu")"
    [[ -n "$DRIVER_CHIPSET_RECO_PKGS" ]] && DRIVER_SELECTED_GROUPS="$(dedupe_word_list "$DRIVER_SELECTED_GROUPS chipset")"
    [[ -n "$DRIVER_NETWORK_RECO_PKGS" ]] && DRIVER_SELECTED_GROUPS="$(dedupe_word_list "$DRIVER_SELECTED_GROUPS network")"
    [[ -n "$DRIVER_OTHERS_RECO_PKGS" ]] && DRIVER_SELECTED_GROUPS="$(dedupe_word_list "$DRIVER_SELECTED_GROUPS others")"
    DRIVER_SELECTED_PKGS_PACMAN="$(dedupe_word_list "$DRIVER_GPU_RECO_PKGS $DRIVER_CHIPSET_RECO_PKGS $DRIVER_NETWORK_RECO_PKGS $DRIVER_OTHERS_RECO_PKGS")"
  fi
}

tui_session_display_label() {
  if [[ "$1" == "custom" ]]; then
    printf 'Custom\n'
  else
    session_label "$1"
  fi
}

tui_shell_choice_label() {
  case "$1" in
    fish) printf 'Fish\n' ;;
    oh-my-zsh) printf 'Oh-My-Zsh\n' ;;
    skip) printf 'Skip\n' ;;
    bash|*) printf 'Bash\n' ;;
  esac
}

tui_aur_helper_label() {
  case "$1" in
    yay) printf 'Yay\n' ;;
    paru) printf 'Paru\n' ;;
    skip|*) printf 'Skip\n' ;;
  esac
}

tui_login_method_label() {
  case "$1" in
    display-manager) printf 'Display Manager\n' ;;
    tty-autologin) printf 'TTY Autologin\n' ;;
    manual) printf 'Manual\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

tui_display_manager_label() {
  case "$1" in
    gdm) printf 'GDM\n' ;;
    sddm) printf 'SDDM\n' ;;
    lightdm) printf 'LightDM\n' ;;
    ly) printf 'Ly\n' ;;
    none) printf 'None\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

tui_dm_action_label() {
  case "$1" in
    keep) printf 'Keep\n' ;;
    disable) printf 'Disable\n' ;;
    remove) printf 'Remove\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

tui_driver_mode_label() {
  case "$1" in
    skip) printf 'Skip\n' ;;
    auto) printf 'Auto\n' ;;
    manual) printf 'Manual\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

tui_boot_plymouth_label() {
  case "$1" in
    enable) printf 'Enable\n' ;;
    disable) printf 'Disable\n' ;;
    skip) printf 'Skip\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

tui_bootloader_label() {
  case "$1" in
    grub) printf 'GRUB\n' ;;
    systemd-boot) printf 'Systemd-Boot\n' ;;
    refind) printf 'rEFInd\n' ;;
    limine) printf 'Limine\n' ;;
    no-bootloader) printf 'No Bootloader (UEFI Boot Entry)\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

print_plan() {
  local bootloader_action_display="$BOOTLOADER_ACTION"
  local login_method_display display_manager_display autologin_display autostart_display driver_mode_display boot_tuning_display
  case "$BOOTLOADER_ACTION" in
    keep) bootloader_action_display="Keep Current" ;;
    fix) bootloader_action_display="Fix Current One" ;;
    replace) bootloader_action_display="Replace With Another" ;;
  esac
  login_method_display="$(tui_login_method_label "$LOGIN_METHOD")"
  display_manager_display="$(tui_display_manager_label "$DISPLAY_MANAGER_CHOICE")"
  autologin_display="$( [[ "$AUTOLOGIN_ENABLE" == "yes" ]] && printf 'Yes' || printf 'No' )"
  autostart_display="$( [[ "$AUTOSTART_ENABLE" == "yes" ]] && printf 'Yes' || printf 'No' )"
  driver_mode_display="$(tui_driver_mode_label "$DRIVER_CONFIG_MODE")"
  boot_tuning_display="$( [[ "$BOOT_TUNE_ENABLE" == "yes" ]] && printf 'Yes' || printf 'No' )"
  if [[ "$ARCH_BASE_ENABLE" == "yes" ]]; then
    resolve_arch_plan
  fi

  printf '\n%b╭──────────────────────── PLAN ────────────────────────╮%b\n' "$C_MAUVE" "$C_RESET"
  printf '  %bMode:%b %s\n' "$C_BLUE" "$C_RESET" "$MODE"
  printf '  %bUser:%b %s\n' "$C_BLUE" "$C_RESET" "$TARGET_USER"
  printf '  %bHome:%b %s\n' "$C_BLUE" "$C_RESET" "$TARGET_HOME"
  printf '  %bShell:%b %s\n' "$C_BLUE" "$C_RESET" "$TARGET_SHELL"
  printf '  %bTTY:%b %s\n' "$C_BLUE" "$C_RESET" "$TTY_DEVICE"

  printf '  %bArch Base Module:%b %s\n' "$C_BLUE" "$C_RESET" "$( [[ "$ARCH_BASE_ENABLE" == "yes" ]] && printf 'Yes' || printf 'No' )"
  if [[ "$ARCH_BASE_ENABLE" == "yes" ]]; then
    local pac_all=0 pac_miss=0 aur_all=0 aur_miss=0
    [[ -n "$ARCH_PACMAN_PKGS_RESOLVED" ]] && pac_all=$(wc -w <<<"$ARCH_PACMAN_PKGS_RESOLVED")
    [[ -n "$ARCH_PACMAN_PKGS_MISSING" ]] && pac_miss=$(wc -w <<<"$ARCH_PACMAN_PKGS_MISSING")
    [[ -n "$ARCH_AUR_PKGS_RESOLVED" ]] && aur_all=$(wc -w <<<"$ARCH_AUR_PKGS_RESOLVED")
    [[ -n "$ARCH_AUR_PKGS_MISSING" ]] && aur_miss=$(wc -w <<<"$ARCH_AUR_PKGS_MISSING")
    printf '    Categories: %s\n' "${ARCH_SELECTED_CATEGORIES:-none}"
    printf '    IDEs: %s\n' "${ARCH_SELECTED_IDES:-none}"
    printf '    Apps: %s\n' "${ARCH_SELECTED_APPS:-none}"
    printf '    Custom Apps: %s\n' "${ARCH_CUSTOM_APP_PKGS:-none}"
    printf '    DE/WM Selected: %s\n' "${DEWM_SELECTED:-none}"
    printf '    DE/WM Install Mode: %s\n' "${DEWM_INSTALL_MODE^}"
    printf '    Shell Choice: %s\n' "$(tui_shell_choice_label "$ARCH_SHELL_CHOICE")"
    printf '    Shells: Fish=%s Zsh=%s Oh-My-Zsh=%s\n' "$( [[ "$ARCH_INSTALL_FISH" == "yes" ]] && printf 'Yes' || printf 'No' )" "$( [[ "$ARCH_INSTALL_ZSH" == "yes" ]] && printf 'Yes' || printf 'No' )" "$( [[ "$ARCH_INSTALL_OH_MY_ZSH" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Mirror Optimize: %s\n' "$( [[ "$ARCH_OPTIMIZE_MIRRORS" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Multilib: %s\n' "$( [[ "$ARCH_ENABLE_MULTILIB" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Core-Testing: %s\n' "$( [[ "$ARCH_ENABLE_CORE_TESTING" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Extra-Testing: %s\n' "$( [[ "$ARCH_ENABLE_EXTRA_TESTING" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Multilib-Testing: %s\n' "$( [[ "$ARCH_ENABLE_MULTILIB_TESTING" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Chaotic AUR: %s\n' "$( [[ "$ARCH_ENABLE_CHAOTIC_AUR" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    AUR Helper: %s\n' "$(tui_aur_helper_label "$ARCH_AUR_HELPER")"
    printf '    Pacman: Total=%d Missing=%d\n' "$pac_all" "$pac_miss"
    printf '    AUR: Total=%d Missing=%d\n' "$aur_all" "$aur_miss"
  fi

  printf '  %bLogin Method:%b %s\n' "$C_BLUE" "$C_RESET" "$login_method_display"
  printf '  %bDisplay Manager:%b %s\n' "$C_BLUE" "$C_RESET" "$display_manager_display"
  printf '  %bAutologin:%b %s\n' "$C_BLUE" "$C_RESET" "$autologin_display"
  if [[ "$LOGIN_METHOD" == "tty-autologin" && "$AUTOLOGIN_ENABLE" == "yes" ]]; then
    printf '  %bTTY DM Action:%b %s (Detected: %s)\n' "$C_BLUE" "$C_RESET" "$(tui_dm_action_label "$AUTOLOGIN_DM_ACTION")" "$DETECTED_DM"
  fi
  printf '  %bAutostart (TTY):%b %s\n' "$C_BLUE" "$C_RESET" "$autostart_display"
  if [[ "$LOGIN_METHOD" == "tty-autologin" && "$AUTOSTART_ENABLE" == "yes" ]]; then
    printf '  %bSession:%b %s\n' "$C_BLUE" "$C_RESET" "$(tui_session_display_label "$SESSION_CHOICE")"
    printf '  %bInstall Missing Session:%b %s\n' "$C_BLUE" "$C_RESET" "$( [[ "$AUTOSTART_INSTALL_MISSING_SESSION" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '  %bSession Install Profile:%b %s\n' "$C_BLUE" "$C_RESET" "${AUTOSTART_SESSION_INSTALL_PROFILE^}"
    printf '  %bCommand:%b %s\n' "$C_BLUE" "$C_RESET" "$(get_autostart_command)"
  fi
  printf '  %bDriver Configuration:%b %s\n' "$C_BLUE" "$C_RESET" "$driver_mode_display"
  if [[ "$DRIVER_CONFIG_MODE" != "skip" ]]; then
    printf '    Groups: %s\n' "${DRIVER_SELECTED_GROUPS:-none}"
    printf '    Pacman Packages: %s\n' "${DRIVER_SELECTED_PKGS_PACMAN:-none}"
    printf '    AUR Packages: %s\n' "${DRIVER_SELECTED_PKGS_AUR:-none}"
  fi
  printf '  %bBoot Tuning:%b %s\n' "$C_BLUE" "$C_RESET" "$boot_tuning_display"
  printf '  %bBootloader Action:%b %s\n' "$C_BLUE" "$C_RESET" "$bootloader_action_display"
  if [[ "$BOOTLOADER_ACTION" == "replace" ]]; then
    printf '    Replacement Bootloader: %s\n' "$(tui_bootloader_label "$BOOTLOADER_CHOICE")"
  fi
  if [[ "$BOOT_TUNE_ENABLE" == "yes" ]]; then
    printf '    Silent Boot: %s\n' "$( [[ "$BOOT_SILENT" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    OS-Prober: %s\n' "$( [[ "$BOOT_OS_PROBER" == "yes" ]] && printf 'Yes' || printf 'No' )"
    printf '    Plymouth: %s\n' "$(tui_boot_plymouth_label "$BOOT_PLYMOUTH_ACTION")"
  fi
  printf '%b╰───────────────────────────────────────────────────────╯%b\n' "$C_MAUVE" "$C_RESET"
}

post_checks() {
  echo
  echo "Post-checks:"
  local pass=0 fail=0

  if [[ "$ARCH_BASE_ENABLE" == "yes" ]]; then
    local must_bins=(git curl)
    local b
    for b in "${must_bins[@]}"; do
      if command -v "$b" >/dev/null 2>&1; then
        echo "  [OK] $b present"
        pass=$((pass+1))
      else
        echo "  [FAIL] $b missing"
        fail=$((fail+1))
      fi
    done
  fi

  if [[ "$FILE_MANAGER_CHOICE" != "skip" && "$FILE_MANAGER_CHOICE" != "s" ]]; then
    if pacman -Q "$FILE_MANAGER_CHOICE" >/dev/null 2>&1 || [[ "$FILE_MANAGER_CHOICE" == "pcmanfm" && $(pacman -Q pcmanfm >/dev/null 2>&1; echo $?) -eq 0 ]]; then
      echo "  [OK] File manager package present"
      pass=$((pass+1))
    else
      echo "  [FAIL] File manager package not found"
      fail=$((fail+1))
    fi
  fi

  local fm_app
  for fm_app in thunar nautilus dolphin pcmanfm nemo; do
    if list_has "$ARCH_SELECTED_APPS" "$fm_app"; then
      local check_pkg="$fm_app"
      [[ "$fm_app" == "pcmanfm" ]] && check_pkg="pcmanfm"
      if pacman -Q "$check_pkg" >/dev/null 2>&1; then
        echo "  [OK] App-selected file manager present: $check_pkg"
        pass=$((pass+1))
      else
        echo "  [FAIL] App-selected file manager missing: $check_pkg"
        fail=$((fail+1))
      fi
    fi
  done

  local expected_auth_pkg=""
  for fm_app in thunar nautilus dolphin pcmanfm nemo; do
    if list_has "$ARCH_SELECTED_APPS" "$fm_app"; then
      expected_auth_pkg="$(resolve_auth_agent_pkg)"
      break
    fi
  done
  if [[ -n "$expected_auth_pkg" ]]; then
    if pacman -Q "$expected_auth_pkg" >/dev/null 2>&1; then
      echo "  [OK] Authentication agent package present: $expected_auth_pkg"
      pass=$((pass+1))
    else
      echo "  [FAIL] Authentication agent package missing: $expected_auth_pkg"
      fail=$((fail+1))
    fi
  fi

  if [[ "$AUTOLOGIN_ENABLE" == "yes" ]]; then
    local f="/etc/systemd/system/getty@${TTY_DEVICE}.service.d/autologin.conf"
    if [[ -f "$f" ]]; then
      echo "  [OK] Autologin drop-in exists"
      pass=$((pass+1))
    else
      echo "  [FAIL] Missing autologin drop-in"
      fail=$((fail+1))
    fi
  fi

  if [[ "$AUTOSTART_ENABLE" == "yes" ]]; then
    if grep -qF "$MARK_START" "$SHELL_RC_FILE" 2>/dev/null; then
      echo "  [OK] Shell autostart block present"
      pass=$((pass+1))
    else
      echo "  [FAIL] Shell autostart block missing"
      fail=$((fail+1))
    fi
  fi

  echo "Summary: pass=$pass fail=$fail"
}

launch_modular_wizard() {
  local script_dir wizard_main python_bin
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  wizard_main="$script_dir/setup/main.py"
  python_bin="${PYTHON_BIN:-python3}"

  [[ -t 0 && -t 1 ]] || return 125
  [[ "${ARCTYX_USE_LEGACY_BASH_UI:-0}" != "1" ]] || return 125
  command -v "$python_bin" >/dev/null 2>&1 || return 125
  [[ -f "$wizard_main" ]] || return 125

  PYTHONDONTWRITEBYTECODE=1 "$python_bin" "$wizard_main" --action wizard
}

main() {
  local wizard_rc
  mkdir -p "$BACKUP_ROOT" "$PROFILE_ROOT"
  parse_cli_args "$@"
  if [[ ! -t 0 || ! -t 1 ]]; then
    err "Arctyx setup.sh now launches only the modular wizard and requires an interactive TTY. Use python setup/main.py --action plan/apply/rollback/uninstall for non-interactive runs."
    exit 1
  fi
  startup_prepare_runtime
  if launch_modular_wizard; then
    exit 0
  fi
  wizard_rc=$?

  if [[ "$wizard_rc" -ne 125 ]]; then
    exit "$wizard_rc"
  fi

  err "Failed to launch the Arctyx modular wizard. Legacy Bash UI flow has been removed."
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
