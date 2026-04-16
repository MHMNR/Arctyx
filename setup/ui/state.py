from __future__ import annotations

import getpass
import os
import pwd
import re
import subprocess
from dataclasses import dataclass, field
from typing import Any


MARK_START = "# >>> tty_autostart_managed >>>"
MARK_END = "# <<< tty_autostart_managed <<<"


PACKAGE_CATEGORY_CHOICES = [
    ("core-system", "Core CLI Tools", "Installs the essential command-line base set used in almost every Arctyx setup."),
    ("cli-utils", "CLI Utils", "Adds everyday terminal utilities such as git, curl, nano, Neovim, ripgrep, and fastfetch."),
    ("dev-toolchain", "Development Toolchain", "Installs common compilers and language tooling for building most projects."),
    ("networking", "Networking Tools", "Adds connection management and troubleshooting tools like NetworkManager and DNS utilities."),
    ("desktop-common", "Desktop Common Utilities", "Adds desktop integration packages such as GVFS, archive helpers, and xdg-utils."),
]

SHELL_CHOICES = [
    ("bash", "Bash", "Keeps the classic Bash workflow with minimal extra setup."),
    ("fish", "Fish", "Installs Fish for a modern shell experience with friendly defaults and good completions."),
    ("oh-my-zsh", "Oh-My-Zsh", "Uses Zsh with Oh My Zsh for plugins, themes, and a more customized shell environment."),
]

AUR_HELPER_CHOICES = [
    ("yay", "Yay", "Popular AUR helper with a familiar pacman-like workflow."),
    ("paru", "Paru", "Alternative AUR helper with strong performance and clean dependency handling."),
    ("skip", "Skip", "Do not install an AUR helper; AUR packages will stay unmanaged unless you add one later."),
]

# Known conflicting desktop environment groups (IDs from DESKTOP_CHOICES)
# These cannot typically coexist in a single pacman transaction due to binary or dependency conflicts.
DE_CONFLICT_GROUPS = [
    {"plasma", "deepin"},  # Conflicts on kwin / deepin-kwin
    {"gnome", "pantheon"},  # Frequently conflict on gnome-session/settings-daemon versions
    {"budgie", "pantheon"}, # Version mismatch on mutter (mutter vs mutter46)
]

MIRROR_REGION_CHOICES = [
    ("auto", "Auto select the fastest mirror", "Use Reflector with the Arch Wiki fastest-mirror method.\nReflector flags: --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"),
    # South Asia
    ("region:south_asia", "--- [ South Asia ] ---", "Select all countries in South Asia"),
    ("Bangladesh", "  Bangladesh", "South Asia"),
    ("India", "  India", "South Asia"),
    ("Pakistan", "  Pakistan", "South Asia"),
    # Southeast Asia
    ("region:southeast_asia", "--- [ Southeast Asia ] ---", "Select all countries in Southeast Asia"),
    ("Singapore", "  Singapore", "Southeast Asia"),
    ("Indonesia", "  Indonesia", "Southeast Asia"),
    ("Thailand", "  Thailand", "Southeast Asia"),
    ("Vietnam", "  Vietnam", "Southeast Asia"),
    ("Malaysia", "  Malaysia", "Southeast Asia"),
    ("Philippines", "  Philippines", "Southeast Asia"),
    # East Asia
    ("region:east_asia", "--- [ East Asia ] ---", "Select all countries in East Asia"),
    ("Japan", "  Japan", "East Asia"),
    ("South Korea", "  South Korea", "East Asia"),
    ("Taiwan", "  Taiwan", "East Asia"),
    ("Hong Kong", "  Hong Kong", "East Asia"),
    # Middle East
    ("region:middle_east", "--- [ Middle East ] ---", "Select all countries in Middle East"),
    ("Israel", "  Israel", "Middle East"),
    ("Turkey", "  Turkey", "Middle East"),
    # Oceania
    ("region:oceania", "--- [ Oceania ] ---", "Select all countries in Oceania"),
    ("Australia", "  Australia", "Oceania"),
    ("New Zealand", "  New Zealand", "Oceania"),
    # Western Europe
    ("region:western_europe", "--- [ Western Europe ] ---", "Select all countries in Western Europe"),
    ("France", "  France", "Western Europe"),
    ("Germany", "  Germany", "Western Europe"),
    ("Netherlands", "  Netherlands", "Western Europe"),
    ("Belgium", "  Belgium", "Western Europe"),
    ("Luxembourg", "  Luxembourg", "Western Europe"),
    ("Austria", "  Austria", "Western Europe"),
    ("Switzerland", "  Switzerland", "Western Europe"),
    # Northern Europe
    ("region:northern_europe", "--- [ Northern Europe ] ---", "Select all countries in Northern Europe"),
    ("United Kingdom", "  United Kingdom", "Northern Europe"),
    ("Denmark", "  Denmark", "Northern Europe"),
    ("Sweden", "  Sweden", "Northern Europe"),
    ("Norway", "  Norway", "Northern Europe"),
    ("Finland", "  Finland", "Northern Europe"),
    ("Iceland", "  Iceland", "Northern Europe"),
    ("Ireland", "  Ireland", "Northern Europe"),
    # Southern Europe
    ("region:southern_europe", "--- [ Southern Europe ] ---", "Select all countries in Southern Europe"),
    ("Spain", "  Spain", "Southern Europe"),
    ("Portugal", "  Portugal", "Southern Europe"),
    ("Italy", "  Italy", "Southern Europe"),
    ("Greece", "  Greece", "Southern Europe"),
    # Eastern Europe
    ("region:eastern_europe", "--- [ Eastern Europe ] ---", "Select all countries in Eastern Europe"),
    ("Poland", "  Poland", "Eastern Europe"),
    ("Czechia", "  Czechia", "Eastern Europe"),
    ("Slovakia", "  Slovakia", "Eastern Europe"),
    ("Hungary", "  Hungary", "Eastern Europe"),
    ("Romania", "  Romania", "Eastern Europe"),
    ("Bulgaria", "  Bulgaria", "Eastern Europe"),
    ("Croatia", "  Croatia", "Eastern Europe"),
    ("Serbia", "  Serbia", "Eastern Europe"),
    ("Slovenia", "  Slovenia", "Eastern Europe"),
    ("Ukraine", "  Ukraine", "Eastern Europe"),
    # North America
    ("region:north_america", "--- [ North America ] ---", "Select all countries in North America"),
    ("United States", "  United States", "North America"),
    ("Canada", "  Canada", "North America"),
    # Central America
    ("region:central_america", "--- [ Central America ] ---", "Select all countries in Central America"),
    ("Mexico", "  Mexico", "Central America"),
    ("Costa Rica", "  Costa Rica", "Central America"),
    ("Puerto Rico", "  Puerto Rico", "Central America"),
    # South America
    ("region:south_america", "--- [ South America ] ---", "Select all countries in South America"),
    ("Brazil", "  Brazil", "South America"),
    ("Argentina", "  Argentina", "South America"),
    ("Chile", "  Chile", "South America"),
    ("Colombia", "  Colombia", "South America"),
    ("Ecuador", "  Ecuador", "South America"),
    ("Paraguay", "  Paraguay", "South America"),
    ("Peru", "  Peru", "South America"),
    ("Uruguay", "  Uruguay", "South America"),
    # Africa
    ("region:africa", "--- [ Africa ] ---", "Select all countries in Africa"),
    ("South Africa", "  South Africa", "Africa"),
    ("Kenya", "  Kenya", "Africa"),
]

MIRROR_COUNTRY_MAP: dict[str, list[str]] = {
    "region:south_asia": ["Bangladesh", "India", "Pakistan"],
    "region:southeast_asia": ["Singapore", "Indonesia", "Thailand", "Vietnam", "Malaysia", "Philippines"],
    "region:east_asia": ["Japan", "South Korea", "Taiwan", "Hong Kong"],
    "region:middle_east": ["Israel", "Turkey"],
    "region:oceania": ["Australia", "New Zealand"],
    "region:western_europe": ["France", "Germany", "Netherlands", "Belgium", "Luxembourg", "Austria", "Switzerland"],
    "region:northern_europe": ["United Kingdom", "Denmark", "Sweden", "Norway", "Finland", "Iceland", "Ireland"],
    "region:southern_europe": ["Spain", "Portugal", "Italy", "Greece"],
    "region:eastern_europe": ["Poland", "Czechia", "Slovakia", "Hungary", "Romania", "Bulgaria", "Croatia", "Serbia", "Slovenia", "Ukraine"],
    "region:north_america": ["United States", "Canada"],
    "region:central_america": ["Mexico", "Costa Rica", "Puerto Rico"],
    "region:south_america": ["Brazil", "Argentina", "Chile", "Colombia", "Ecuador", "Paraguay", "Peru", "Uruguay"],
    "region:africa": ["South Africa", "Kenya"],
}

APP_CATEGORIES: dict[str, dict[str, Any]] = {
    "file_managers": {
        "label": "File Managers",
        "items": [
            ("thunar", "Thunar", "app"),
            ("nautilus", "Nautilus", "app"),
            ("dolphin", "Dolphin", "app"),
            ("pcmanfm", "PCManFM", "app"),
            ("nemo", "Nemo", "app"),
            ("krusader", "Krusader", "app"),
            ("ranger", "Ranger", "app"),
            ("yazi", "Yazi", "app"),
        ],
    },
    "terminals": {
        "label": "Terminals",
        "items": [
            ("kitty", "Kitty", "app"),
            ("alacritty", "Alacritty", "app"),
            ("wezterm", "WezTerm", "app"),
            ("foot", "Foot", "app"),
            ("ghostty", "Ghostty", "app"),
        ],
    },
    "development_tools": {
        "label": "Development Tools",
        "items": [
            ("android-studio", "Android Studio", "ide"),
            ("antigravity", "Antigravity", "ide"),
            ("code", "VS Code", "ide"),
            ("codium", "VSCodium", "ide"),
            ("cursor", "Cursor", "ide"),
            ("zed", "Zed", "ide"),
            ("neovim", "Neovim", "ide"),
            ("emacs", "Emacs", "ide"),
            ("lazygit", "Lazygit", "app"),
            ("gitui", "GitUI", "app"),
            ("helix", "Helix", "ide"),
            ("sublime-text", "Sublime Text", "ide"),
            ("jetbrains-toolbox", "JetBrains Toolbox", "ide"),
            ("meld", "Meld", "app"),
            ("docker-desktop", "Docker Desktop", "app"),
        ],
    },
    "browsers": {
        "label": "Browsers",
        "items": [
            ("firefox", "Firefox", "app"),
            ("chromium", "Chromium", "app"),
            ("chrome", "Google Chrome", "app"),
            ("brave", "Brave", "app"),
            ("waterfox", "Waterfox", "app"),
            ("zen", "Zen Browser", "app"),
            ("librewolf", "LibreWolf", "app"),
            ("floorp", "Floorp", "app"),
            ("qutebrowser", "Qutebrowser", "app"),
            ("vivaldi", "Vivaldi", "app"),
        ],
    },
    "media": {
        "label": "Graphics and Video",
        "items": [
            ("vlc", "VLC", "app"),
            ("mpv", "MPV", "app"),
            ("gimp", "GIMP", "app"),
            ("krita", "Krita", "app"),
            ("inkscape", "Inkscape", "app"),
            ("darktable", "Darktable", "app"),
            ("kdenlive", "Kdenlive", "app"),
            ("shotcut", "Shotcut", "app"),
            ("davinci-resolve", "DaVinci Resolve", "app"),
            ("obs-studio", "OBS Studio", "app"),
            ("blender", "Blender", "app"),
            ("audacity", "Audacity", "app"),
            ("handbrake", "HandBrake", "app"),
        ],
    },
    "messaging": {
        "label": "Messaging and Mail",
        "items": [
            ("telegram-desktop", "Telegram Desktop", "app"),
            ("signal-desktop", "Signal Desktop", "app"),
            ("element-desktop", "Element", "app"),
            ("vesktop", "Vesktop", "app"),
            ("slack-desktop", "Slack", "app"),
            ("ferdium", "Ferdium", "app"),
            ("zoom", "Zoom", "app"),
            ("thunderbird", "Thunderbird", "app"),
        ],
    },
    "utilities": {
        "label": "Utilities",
        "items": [
            ("virtualbox", "Oracle VirtualBox", "app"),
            ("virt-manager", "QEMU / Virt-Manager", "app"),
            ("localsend", "LocalSend", "app"),
            ("balena-etcher", "Balena Etcher", "app"),
            ("ventoy", "Ventoy", "app"),
            ("freedownloadmanager", "Free Download Manager", "app"),
            ("ab-download-manager", "AB Download Manager", "app"),
            ("xdman", "Xtreme Download Manager", "app"),
            ("gparted", "GParted", "app"),
            ("baobab", "Baobab", "app"),
            ("filezilla", "FileZilla", "app"),
            ("syncthing", "Syncthing", "app"),
            ("kdeconnect", "KDE Connect", "app"),
            ("keepassxc", "KeePassXC", "app"),
            ("flameshot", "Flameshot", "app"),
            ("remmina", "Remmina", "app"),
            ("qbittorrent", "qBittorrent", "app"),
            ("timeshift", "Timeshift", "app"),
            ("flatseal", "Flatseal", "app"),
        ],
    },
    "music_audio": {
        "label": "Music and Audio",
        "items": [
            ("spotify", "Spotify", "app"),
            ("strawberry", "Strawberry", "app"),
            ("amberol", "Amberol", "app"),
            ("cmus", "cmus", "app"),
            ("easyeffects", "EasyEffects", "app"),
            ("pavucontrol", "PavuControl", "app"),
        ],
    },
    "gaming": {
        "label": "Gaming",
        "items": [
            ("steam", "Steam", "app"),
            ("wine", "Wine", "app"),
            ("lutris", "Lutris", "app"),
            ("gamemode", "GameMode", "app"),
            ("mangohud", "MangoHud", "app"),
            ("heroic", "Heroic Games Launcher", "app"),
            ("prismlauncher", "Prism Launcher", "app"),
            ("bottles", "Bottles", "app"),
            ("discord", "Discord", "app"),
            ("goverlay", "GOverlay", "app"),
        ],
    },
    "reading_docs": {
        "label": "Reading and PDF",
        "items": [
            ("okular", "Okular", "app"),
            ("evince", "Evince", "app"),
            ("zathura", "Zathura", "app"),
            ("calibre", "Calibre", "app"),
            ("foliate", "Foliate", "app"),
            ("papers", "Papers", "app"),
        ],
    },
    "office_apps": {
        "label": "Office Apps",
        "items": [
            ("libreoffice-fresh", "LibreOffice", "app"),
            ("onlyoffice-bin", "ONLYOFFICE", "app"),
            ("obsidian", "Obsidian", "app"),
            ("joplin", "Joplin", "app"),
        ],
    },
    "custom": {
        "label": "Custom Packages",
        "items": [],
    },
}

DESKTOP_CHOICES = [
    ("hyprland", "Hyprland"),
    ("sway", "Sway"),
    ("river", "River"),
    ("wayfire", "Wayfire"),
    ("labwc", "Labwc"),
    ("niri", "Niri"),
    ("plasma", "Plasma"),
    ("gnome", "GNOME"),
    ("xfce", "XFCE"),
    ("cinnamon", "Cinnamon"),
    ("mate", "MATE"),
    ("lxqt", "LXQt"),
    ("budgie", "Budgie"),
    ("deepin", "Deepin"),
    ("pantheon", "Pantheon"),
    ("i3", "i3"),
    ("bspwm", "Bspwm"),
    ("awesome", "Awesome"),
    ("openbox", "Openbox"),
]

DESKTOP_PROFILE_CHOICES = [
    ("full", "Full", "Installs a fuller desktop profile with more defaults and convenience packages."),
    ("core", "Core", "Keeps the desktop profile lean with a smaller package set."),
]

LOGIN_METHOD_CHOICES = [
    ("display-manager", "Display Manager", "Uses a graphical login manager such as GDM or SDDM."),
    ("tty-autologin", "TTY Autologin", "Logs into a TTY automatically, then optionally starts a session or command."),
    ("manual", "Manual", "Leaves login fully manual with no autologin behavior."),
]

DISPLAY_MANAGER_CHOICES = [
    ("gdm", "GDM", "GNOME Display Manager; a strong default for GNOME and Wayland-friendly setups."),
    ("sddm", "SDDM", "Common display manager for Plasma and many desktop environments."),
    ("lightdm", "LightDM", "Lightweight display manager with broad desktop support."),
    ("ly", "Ly", "Console-based display manager for users who want a lighter login experience."),
]

AUTOSTART_SESSION_CHOICES = DESKTOP_CHOICES + [("custom", "Custom Command", "Runs a custom command after login instead of a predefined desktop session.")]

INSTALL_PROFILE_CHOICES = [
    ("core", "Core", "Installs only the core package set needed for the selected session."),
    ("full", "Full", "Installs the selected session with extra supporting packages and defaults."),
]

AUTOSTART_ACTION_CHOICES = [
    ("on", "On", "Enable Arctyx-managed TTY autostart and configure a session or custom command."),
    ("off", "Off", "Disable the current Arctyx-managed TTY autostart block if one exists."),
    ("skip", "Skip", "Leave the current autostart state untouched."),
]

DRIVER_CHOICES = [
    ("skip", "Skip Driver Install", "Leaves driver selection untouched and skips Arctyx-managed driver setup."),
    ("auto", "Auto Detect And Install", "Lets Arctyx detect common hardware and install recommended drivers automatically."),
    ("manual", "Manual Selection", "Choose driver categories and packages yourself."),
]

DRIVER_GROUPS: dict[str, dict[str, Any]] = {
    "gpu": {
        "label": "GPU",
        "items": [
            ("nvidia-580xx-dkms", "nvidia-580xx-dkms"),
            ("nvidia-open-dkms", "nvidia-open-dkms"),
            ("nvidia-open", "nvidia-open"),
            ("nvidia-dkms", "nvidia-dkms"),
            ("nvidia", "nvidia"),
            ("nvidia-utils", "nvidia-utils"),
            ("nvidia-settings", "nvidia-settings"),
            ("egl-wayland", "egl-wayland"),
            ("linux-headers", "linux-headers"),
            ("mesa", "mesa"),
            ("vulkan-radeon", "vulkan-radeon"),
            ("libva-mesa-driver", "libva-mesa-driver"),
            ("lib32-mesa", "lib32-mesa"),
            ("lib32-vulkan-radeon", "lib32-vulkan-radeon"),
            ("lib32-libva-mesa-driver", "lib32-libva-mesa-driver"),
            ("vulkan-intel", "vulkan-intel"),
            ("lib32-vulkan-intel", "lib32-vulkan-intel"),
            ("intel-media-driver", "intel-media-driver"),
            ("xf86-video-amdgpu", "xf86-video-amdgpu"),
        ],
    },
    "chipset": {
        "label": "Chipset",
        "items": [
            ("intel-ucode", "intel-ucode"),
            ("amd-ucode", "amd-ucode"),
            ("fwupd", "fwupd"),
        ],
    },
    "network": {
        "label": "Network",
        "items": [
            ("networkmanager", "networkmanager"),
            ("iwd", "iwd"),
            ("wpa_supplicant", "wpa_supplicant"),
            ("bluez", "bluez"),
            ("bluez-utils", "bluez-utils"),
            ("broadcom-wl-dkms", "broadcom-wl-dkms"),
        ],
    },
    "others": {
        "label": "Others",
        "items": [
            ("linux-firmware", "linux-firmware"),
            ("sof-firmware", "sof-firmware"),
        ],
    },
}

SPLASH_MODE_CHOICES = [
    ("skip", "Skip", "Leave the current boot output mode unchanged."),
    ("silent", "Silent / Blank", "Hide all boot text and boot completely silently to a blank screen until login."),
    ("plymouth", "Plymouth Splash", "Hide text and display a clean graphical loading animation (requires plymouth)."),
    ("verbose", "Verbose Text", "Show standard linux kernel and systemd boot messages."),
]

OS_PROBER_CHOICES = [
    ("skip", "Skip", "Leave the current OS-Prober setting unchanged."),
    ("on", "Enable", "Allow GRUB to detect and add other operating systems to the boot menu."),
    ("off", "Disable", "Stop GRUB from scanning for other operating systems."),
]

BOOTLOADER_ACTION_CHOICES = [
    ("keep", "Keep Current", "Leave the current bootloader untouched and only apply the other boot tuning choices below."),
    ("fix", "Fix Current One", "Detect the currently installed bootloader and reinstall that same one cleanly.\nPackages: depends on the detected bootloader."),
    ("replace", "Replace With Another", "Replace the current bootloader with another one you choose in the next step."),
]

BOOTLOADER_CHOICES = [
    ("grub", "GRUB", "Install or repair GRUB.\nPackages: grub, efibootmgr"),
    ("systemd-boot", "Systemd-Boot", "Install or repair Systemd-Boot.\nPackages: systemd, efibootmgr"),
    ("refind", "rEFInd", "Install or repair rEFInd.\nPackages: refind, efibootmgr"),
    ("limine", "Limine", "Install Limine packages and attempt a best-effort setup.\nPackages: limine"),
    ("no-bootloader", "No Bootloader (UEFI Boot Entry)", "Skip a traditional bootloader and create a direct UEFI boot entry.\nPackages: efibootmgr"),
]


def detect_current_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    try:
        return getpass.getuser()
    except Exception:
        return "root"


def detect_user_shell(username: str) -> str:
    try:
        return pwd.getpwnam(username).pw_shell or "/bin/bash"
    except KeyError:
        return "/bin/bash"


def detect_user_home(username: str) -> str:
    try:
        return pwd.getpwnam(username).pw_dir
    except KeyError:
        return os.path.expanduser(f"~{username}")


def detect_plymouth_enabled() -> bool:
    hooks_has_plymouth = False
    cmdline_has_splash = False
    package_installed = False
    unit_enabled = False

    try:
        if os.path.isfile("/etc/mkinitcpio.conf"):
            with open("/etc/mkinitcpio.conf", "r", encoding="utf-8", errors="ignore") as handle:
                for line in handle:
                    if line.startswith("HOOKS=") and "plymouth" in line:
                        hooks_has_plymouth = True
                        break
    except OSError:
        pass

    try:
        with open("/etc/default/grub", "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                if line.startswith("GRUB_CMDLINE_LINUX_DEFAULT=") and "splash" in line:
                    cmdline_has_splash = True
                    break
    except OSError:
        pass

    try:
        package_installed = subprocess.run(
            ["pacman", "-Q", "plymouth"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode == 0
    except FileNotFoundError:
        package_installed = False

    try:
        unit_enabled = subprocess.run(
            ["systemctl", "is-enabled", "plymouth-start.service"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode == 0
    except FileNotFoundError:
        unit_enabled = False

    return hooks_has_plymouth or cmdline_has_splash or package_installed or unit_enabled


def _shell_rc_file(shell_path: str, home_dir: str) -> str:
    shell_name = os.path.basename(shell_path).lower()
    if shell_name == "fish":
        return os.path.join(home_dir, ".config", "fish", "config.fish")
    if shell_name == "zsh":
        return os.path.join(home_dir, ".zshrc")
    return os.path.join(home_dir, ".bashrc")


def _candidate_shell_rc_files(home_dir: str, shell_path: str) -> list[str]:
    preferred = _shell_rc_file(shell_path, home_dir)
    candidates = [
        preferred,
        os.path.join(home_dir, ".bashrc"),
        os.path.join(home_dir, ".zshrc"),
        os.path.join(home_dir, ".config", "fish", "config.fish"),
    ]
    seen: set[str] = set()
    ordered: list[str] = []
    for item in candidates:
        if item in seen:
            continue
        seen.add(item)
        ordered.append(item)
    return ordered


def _detect_tty_autologin_device(username: str) -> tuple[bool, str]:
    systemd_root = "/etc/systemd/system"
    if not os.path.isdir(systemd_root):
        return False, "tty1"

    for entry in os.listdir(systemd_root):
        if not entry.startswith("getty@") or not entry.endswith(".service.d"):
            continue
        tty_device = entry[len("getty@") : -len(".service.d")]
        dropin = os.path.join(systemd_root, entry, "autologin.conf")
        if not os.path.isfile(dropin):
            continue
        try:
            with open(dropin, "r", encoding="utf-8", errors="ignore") as handle:
                content = handle.read()
        except OSError:
            continue
        if f"--autologin {username}" in content:
            return True, tty_device

    return False, "tty1"


def _detect_enabled_display_manager() -> str:
    service_map = {
        "gdm": "gdm.service",
        "sddm": "sddm.service",
        "lightdm": "lightdm.service",
        "ly": "ly.service",
    }
    for dm_key, service_name in service_map.items():
        try:
            result = subprocess.run(
                ["systemctl", "is-enabled", service_name],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except FileNotFoundError:
            return "none"
        if result.returncode == 0:
            return dm_key
    return "none"


def detect_current_login(username: str) -> dict[str, Any]:
    tty_autologin, tty_device = _detect_tty_autologin_device(username)
    display_manager = _detect_enabled_display_manager()
    if tty_autologin:
        return {
            "method": "tty-autologin",
            "display_manager": "none",
            "autologin": True,
            "tty_device": tty_device,
        }
    if display_manager != "none":
        return {
            "method": "display-manager",
            "display_manager": display_manager,
            "autologin": False,
            "tty_device": "tty1",
        }
    return {
        "method": "manual",
        "display_manager": "none",
        "autologin": False,
        "tty_device": "tty1",
    }


def _detect_session_from_command(command: str) -> str:
    normalized = command.strip()
    mapping = [
        ("start-hyprland", "hyprland"),
        ("Hyprland", "hyprland"),
        ("wayfire", "wayfire"),
        ("labwc", "labwc"),
        ("startplasma-wayland", "plasma"),
        ("startplasma-x11", "plasma"),
        ("gnome-session --session=pantheon", "pantheon"),
        ("gnome-session", "gnome"),
        ("startxfce4", "xfce"),
        ("sway", "sway"),
        ("river", "river"),
        ("niri-session", "niri"),
        ("niri", "niri"),
        ("cinnamon-session", "cinnamon"),
        ("mate-session", "mate"),
        ("startlxqt", "lxqt"),
        ("budgie-desktop", "budgie"),
        ("startdde", "deepin"),
        ("pantheon-session", "pantheon"),
        ("openbox-session", "openbox"),
        ("awesome", "awesome"),
        ("bspwm", "bspwm"),
        ("i3", "i3"),
    ]
    for needle, session in mapping:
        if needle in normalized:
            return session
    return "custom"


def detect_current_autostart(username: str, shell_path: str) -> dict[str, Any]:
    detected = {
        "autologin": False,
        "tty_device": "tty1",
        "autostart_enabled": False,
        "autostart_session": "hyprland",
        "autostart_custom_command": "",
    }

    detected["autologin"], detected["tty_device"] = _detect_tty_autologin_device(username)
    home_dir = detect_user_home(username)
    for rc_file in _candidate_shell_rc_files(home_dir, shell_path):
        if not os.path.isfile(rc_file):
            continue
        try:
            with open(rc_file, "r", encoding="utf-8", errors="ignore") as handle:
                content = handle.read()
        except OSError:
            continue

        start = content.find(MARK_START)
        end = content.find(MARK_END)
        if start == -1 or end == -1 or end <= start:
            continue

        block = content[start:end]
        detected["autostart_enabled"] = True

        tty_match = re.search(r'/dev/([A-Za-z0-9._-]+)', block)
        if tty_match:
            detected["tty_device"] = tty_match.group(1)

        exec_match = re.search(r'^\s*exec\s+(.+?)\s*$', block, flags=re.MULTILINE)
        if exec_match:
            command = exec_match.group(1).strip()
            session = _detect_session_from_command(command)
            detected["autostart_session"] = session
            if session == "custom":
                detected["autostart_custom_command"] = command
        return detected

    return detected


def _login_config_is_defaultish(login: dict[str, Any]) -> bool:
    autostart = login.get("autostart", {})
    return (
        login.get("method", "tty-autologin") == "tty-autologin"
        and login.get("display_manager", "none") == "none"
        and bool(login.get("autologin", False)) is False
        and login.get("tty_device", "tty1") == "tty1"
        and bool(autostart.get("enabled", False)) is False
        and autostart.get("session", "hyprland") == "hyprland"
        and autostart.get("command", "") == ""
    )


def shell_choice_from_path(shell_path: str) -> str:
    shell_name = os.path.basename(shell_path).lower()
    if shell_name == "fish":
        return "fish"
    if shell_name == "zsh":
        return "oh-my-zsh"
    return "bash"


def shell_label(choice: str) -> str:
    for value, label, *_detail in SHELL_CHOICES:
        if value == choice:
            return label
    return choice


def choice_label(choice: str, choices: list[tuple]) -> str:
    for value, label, *_detail in choices:
        if value == choice:
            return label
    return choice.replace("-", " ").title()


def package_category_label(choice: str) -> str:
    return choice_label(choice, PACKAGE_CATEGORY_CHOICES)


def aur_helper_label(choice: str) -> str:
    return choice_label(choice, AUR_HELPER_CHOICES)


def desktop_label(choice: str) -> str:
    return choice_label(choice, DESKTOP_CHOICES)


def desktop_profile_label(choice: str) -> str:
    return choice_label(choice, DESKTOP_PROFILE_CHOICES)


def login_method_label(choice: str) -> str:
    return choice_label(choice, LOGIN_METHOD_CHOICES)


def display_manager_label(choice: str) -> str:
    return choice_label(choice, DISPLAY_MANAGER_CHOICES)


def autostart_session_label(choice: str) -> str:
    return choice_label(choice, AUTOSTART_SESSION_CHOICES)


def install_profile_label(choice: str) -> str:
    return choice_label(choice, INSTALL_PROFILE_CHOICES)


def driver_mode_label(choice: str) -> str:
    return choice_label(choice, DRIVER_CHOICES)


def splash_mode_label(choice: str) -> str:
    return choice_label(choice, SPLASH_MODE_CHOICES)


def os_prober_action_label(choice: str) -> str:
    return choice_label(choice, OS_PROBER_CHOICES)


def bootloader_label(choice: str) -> str:
    return choice_label(choice, BOOTLOADER_CHOICES)


def bootloader_action_label(choice: str) -> str:
    return choice_label(choice, BOOTLOADER_ACTION_CHOICES)


def app_label(app_id: str) -> str:
    for category in APP_CATEGORIES.values():
        for value, label, _kind in category["items"]:
            if value == app_id:
                return label
    return app_id


def _bool_label(value: bool) -> str:
    return "Yes" if value else "No"


def mirror_region_label(choice: str) -> str:
    return choice_label(choice, MIRROR_REGION_CHOICES)


def mirror_selection_summary(enabled: bool, regions: list[str]) -> str:
    if not enabled:
        return "Off"
    if not regions or "auto" in regions:
        return "Auto Fastest"
    return ", ".join(mirror_region_label(item) for item in regions)


@dataclass
class WizardState:
    current_user: str = field(default_factory=detect_current_user)
    use_current_user: bool = True
    target_user: str = field(default_factory=detect_current_user)
    detected_shell: str = "/bin/bash"
    shell_choice: str = "bash"
    package_categories: list[str] = field(default_factory=lambda: ["core-system", "cli-utils"])
    optimize_mirrors: bool = False
    mirror_regions: list[str] = field(default_factory=list)
    enable_multilib: bool = False
    enable_chaotic_aur: bool = False
    aur_helper: str = "skip"
    selected_apps: list[str] = field(default_factory=list)
    selected_ides: list[str] = field(default_factory=list)
    custom_apps: list[str] = field(default_factory=list)
    desktop_sessions: list[str] = field(default_factory=list)
    desktop_profile: str = "full"
    login_method: str = "tty-autologin"
    display_manager: str = "none"
    autologin: bool = False
    tty_device: str = "tty1"
    autostart_action: str = "skip"
    autostart_enabled: bool = False
    autostart_session: str = "hyprland"
    autostart_custom_command: str = ""
    detected_autostart_enabled: bool = False
    detected_autostart_session: str = "hyprland"
    detected_autostart_custom_command: str = ""
    detected_login_method: str = "manual"
    detected_display_manager: str = "none"
    autostart_install_missing: bool = False
    autostart_install_profile: str = "core"
    driver_mode: str = "skip"
    driver_groups: list[str] = field(default_factory=list)
    driver_packages: list[str] = field(default_factory=list)
    boot_splash_mode: str = "skip"
    boot_os_prober_action: str = "skip"
    detected_plymouth_enabled: bool = field(default_factory=detect_plymouth_enabled)
    bootloader_action: str = "keep"
    boot_replace_bootloader: bool = False
    bootloader_choice: str = "grub"
    save_profile: bool = False

    @classmethod
    def from_json_state(cls, state: dict[str, Any]) -> "WizardState":
        current_user = detect_current_user()
        user = state.get("user", {})
        packages = state.get("packages", {})
        apps = state.get("apps", {})
        desktop = state.get("desktop", {})
        login = state.get("login", {})
        drivers = state.get("drivers", {})
        boot = state.get("boot", {})
        profile = state.get("profile", {})

        target_user = user.get("target") or current_user
        detected_shell = detect_user_shell(target_user)
        detected_plymouth_enabled = detect_plymouth_enabled()
        detected_login = detect_current_login(target_user)

        shell_choice = packages.get("shell_choice") or shell_choice_from_path(detected_shell)
        desktop_sessions = list(desktop.get("sessions", []))
        autostart = login.get("autostart", {})
        detected_autostart = detect_current_autostart(target_user, detected_shell)

        if _login_config_is_defaultish(login):
            login = {
                **login,
                "method": "tty-autologin",
                "display_manager": detected_login["display_manager"],
                "autologin": detected_login["autologin"],
                "tty_device": detected_login["tty_device"],
                "autostart": {
                    **autostart,
                    "enabled": detected_autostart["autostart_enabled"],
                    "session": detected_autostart["autostart_session"],
                    "command": detected_autostart["autostart_custom_command"],
                },
            }
            login["method"] = detected_login["method"]
            autostart = login.get("autostart", {})

        return cls(
            current_user=current_user,
            use_current_user=bool(user.get("use_current_user", True)),
            target_user=target_user,
            detected_shell=detected_shell,
            shell_choice=shell_choice,
            package_categories=list(packages.get("categories", ["core-system", "cli-utils"])),
            optimize_mirrors=bool(packages.get("optimize_mirrors", False)),
            mirror_regions=list(packages.get("mirror_regions", [])),
            enable_multilib=bool(packages.get("multilib", False)),
            enable_chaotic_aur=bool(packages.get("chaotic_aur", False)),
            aur_helper=packages.get("aur_helper", "skip"),
            selected_apps=list(apps.get("selected", [])),
            selected_ides=list(apps.get("ides", [])),
            custom_apps=list(apps.get("custom", [])),
            desktop_sessions=desktop_sessions,
            desktop_profile=desktop.get("profile", "full"),
            login_method=login.get("method", "tty-autologin"),
            display_manager=login.get("display_manager", "none"),
            autologin=bool(login.get("autologin", False)),
            tty_device=login.get("tty_device", "tty1"),
            autostart_action=autostart.get("action", "on" if autostart.get("enabled", False) else "skip"),
            autostart_enabled=bool(autostart.get("enabled", False)),
            autostart_session=autostart.get("session", "hyprland"),
            autostart_custom_command=autostart.get("command", ""),
            detected_autostart_enabled=bool(detected_autostart["autostart_enabled"]),
            detected_autostart_session=detected_autostart["autostart_session"],
            detected_autostart_custom_command=detected_autostart["autostart_custom_command"],
            detected_login_method=detected_login["method"],
            detected_display_manager=detected_login["display_manager"],
            autostart_install_missing=bool(autostart.get("install_missing", False)),
            autostart_install_profile=autostart.get("install_profile", "core"),
            driver_mode=drivers.get("mode", "skip"),
            driver_groups=list(drivers.get("selected_groups", [])),
            driver_packages=list(drivers.get("pacman_packages", [])),
            boot_splash_mode=boot.get("splash_mode", "skip"),
            boot_os_prober_action=boot.get("os_prober_action", "skip"),
            detected_plymouth_enabled=detected_plymouth_enabled,
            bootloader_action=boot.get("bootloader_action", "replace" if boot.get("replace_bootloader", False) else "keep"),
            boot_replace_bootloader=bool(boot.get("replace_bootloader", False)),
            bootloader_choice=boot.get("bootloader", "grub"),
            save_profile=bool(profile.get("save", False)),
        )

    def sync_target_with_current_user(self) -> None:
        if self.use_current_user:
            self.target_user = self.current_user
        self.detected_shell = detect_user_shell(self.target_user)
        detected_login = detect_current_login(self.target_user)
        detected_autostart = detect_current_autostart(self.target_user, self.detected_shell)
        self.detected_login_method = detected_login["method"]
        self.detected_display_manager = detected_login["display_manager"]
        self.detected_autostart_enabled = bool(detected_autostart["autostart_enabled"])
        self.detected_autostart_session = detected_autostart["autostart_session"]
        self.detected_autostart_custom_command = detected_autostart["autostart_custom_command"]

    def apply_to_json_state(self, state: dict[str, Any]) -> dict[str, Any]:
        self.sync_target_with_current_user()
        state["workflow"]["mode"] = "install"
        state["user"]["use_current_user"] = self.use_current_user
        state["user"]["target"] = self.target_user

        state["packages"]["base_enable"] = bool(self.package_categories)
        state["packages"]["categories"] = list(self.package_categories)
        state["packages"]["shell_choice"] = self.shell_choice
        state["packages"]["optimize_mirrors"] = self.optimize_mirrors
        if not self.optimize_mirrors:
            state["packages"]["mirror_regions"] = []
        elif not self.mirror_regions or "auto" in self.mirror_regions:
            state["packages"]["mirror_regions"] = ["auto"]
        else:
            state["packages"]["mirror_regions"] = list(self.mirror_regions)
        state["packages"]["multilib"] = self.enable_multilib
        state["packages"]["chaotic_aur"] = self.enable_chaotic_aur
        state["packages"]["aur_helper"] = self.aur_helper
        if state["packages"]["base_enable"] and not state["packages"]["categories"]:
            state["packages"]["categories"] = ["core-system", "cli-utils"]

        state["apps"]["selected"] = list(self.selected_apps)
        state["apps"]["ides"] = list(self.selected_ides)
        state["apps"]["custom"] = list(self.custom_apps)

        primary = self.desktop_sessions[0] if self.desktop_sessions else "none"
        state["desktop"]["sessions"] = list(self.desktop_sessions)
        state["desktop"]["primary"] = primary
        state["desktop"]["profile"] = self.desktop_profile

        state["login"]["method"] = self.login_method
        state["login"]["display_manager"] = self.display_manager
        state["login"]["autologin"] = self.autologin
        state["login"]["tty_device"] = self.tty_device
        state["login"]["autostart"]["action"] = self.autostart_action
        state["login"]["autostart"]["enabled"] = self.autostart_action == "on" and self.autostart_enabled
        state["login"]["autostart"]["session"] = self.autostart_session
        state["login"]["autostart"]["command"] = self.autostart_custom_command
        state["login"]["autostart"]["install_missing"] = self.autostart_install_missing
        state["login"]["autostart"]["install_profile"] = self.autostart_install_profile

        state["drivers"]["mode"] = self.driver_mode
        state["drivers"]["selected_groups"] = list(self.driver_groups)
        state["drivers"]["pacman_packages"] = list(self.driver_packages)

        state["boot"]["enabled"] = True
        state["boot"]["splash_mode"] = self.boot_splash_mode
        state["boot"]["os_prober_action"] = self.boot_os_prober_action
        self.boot_replace_bootloader = self.bootloader_action == "replace"
        state["boot"]["bootloader_action"] = self.bootloader_action
        state["boot"]["replace_bootloader"] = self.boot_replace_bootloader
        state["boot"]["bootloader"] = self.bootloader_choice

        state["profile"]["save"] = self.save_profile
        return state

    def count_selected_in_category(self, category_key: str) -> int:
        count = 0
        for value, _label, kind in APP_CATEGORIES[category_key]["items"]:
            if kind == "ide" and value in self.selected_ides:
                count += 1
            elif kind == "app" and value in self.selected_apps:
                count += 1
        if category_key == "custom" and self.custom_apps:
            count = len(self.custom_apps)
        return count

    def selected_category_preview(self, category_key: str, limit: int = 3) -> str:
        if category_key == "custom":
            items = self.custom_apps
        else:
            items = []
            for value, _label, kind in APP_CATEGORIES[category_key]["items"]:
                if kind == "ide" and value in self.selected_ides:
                    items.append(app_label(value))
                elif kind == "app" and value in self.selected_apps:
                    items.append(app_label(value))
        if not items:
            return "None"
        preview = ", ".join(items[:limit])
        if len(items) > limit:
            preview += f" +{len(items) - limit} more"
        return preview

    def summary_lines(self) -> list[str]:
        self.sync_target_with_current_user()
        apps = [app_label(item) for item in self.selected_apps + self.selected_ides]
        if self.custom_apps:
            apps.extend(self.custom_apps)
        package_labels = [package_category_label(item) for item in self.package_categories]
        desktop_labels = [desktop_label(item) for item in self.desktop_sessions]
        driver_group_labels = [DRIVER_GROUPS.get(item, {}).get("label", item.title()) for item in self.driver_groups]
        return [
            f"User: {self.target_user}",
            f"Shell: {shell_label(self.shell_choice)} | AUR: {aur_helper_label(self.aur_helper)}",
            f"Packages: {', '.join(package_labels) if package_labels else 'None'}",
            f"Package Repos: Multilib={_bool_label(self.enable_multilib)} | Chaotic AUR={_bool_label(self.enable_chaotic_aur)} | Mirrors={mirror_selection_summary(self.optimize_mirrors, self.mirror_regions)}",
            f"Apps: {', '.join(apps) if apps else 'None'}",
            f"Desktop: {', '.join(desktop_labels) if desktop_labels else 'None'} ({desktop_profile_label(self.desktop_profile)})",
            f"Login: {login_method_label(self.login_method)} | DM: {display_manager_label(self.display_manager)} | TTY: {self.tty_device}",
            f"Autostart: {self.autostart_action.title()} | Session: {autostart_session_label(self.autostart_session)}",
            f"Drivers: {driver_mode_label(self.driver_mode)} | Groups: {', '.join(driver_group_labels) if driver_group_labels else 'None'}",
            f"Boot: Bootloader Action={bootloader_action_label(self.bootloader_action)} | Bootloader={bootloader_label(self.bootloader_choice)} | Splash Mode={splash_mode_label(self.boot_splash_mode)} | OS-Prober={os_prober_action_label(self.boot_os_prober_action)}",
            f"Save Profile: {_bool_label(self.save_profile)}",
        ]
