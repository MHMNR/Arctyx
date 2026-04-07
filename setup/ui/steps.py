from __future__ import annotations

import pwd
import shutil
import subprocess
from typing import Any

from setup.ui.components import BACK, WizardUI
from setup.ui.intelligence import build_review_report
from setup.ui.state import (
    APP_CATEGORIES,
    app_label,
    AUR_HELPER_CHOICES,
    aur_helper_label,
    AUTOSTART_ACTION_CHOICES,
    AUTOSTART_SESSION_CHOICES,
    autostart_session_label,
    BOOTLOADER_ACTION_CHOICES,
    bootloader_action_label,
    BOOTLOADER_CHOICES,
    bootloader_label,
    DESKTOP_CHOICES,
    desktop_label,
    DESKTOP_PROFILE_CHOICES,
    desktop_profile_label,
    DISPLAY_MANAGER_CHOICES,
    display_manager_label,
    DRIVER_CHOICES,
    DRIVER_GROUPS,
    driver_mode_label,
    INSTALL_PROFILE_CHOICES,
    install_profile_label,
    LOGIN_METHOD_CHOICES,
    login_method_label,
    PACKAGE_CATEGORY_CHOICES,
    package_category_label,
    PLYMOUTH_CHOICES,
    plymouth_action_label,
    SHELL_CHOICES,
    shell_label,
    WizardState,
)

SECTION_ORDER: list[tuple[str, str]] = [
    ("user", "User"),
    ("packages", "Packages"),
    ("apps", "Applications"),
    ("desktop", "Desktop / WM"),
    ("login", "Login"),
    ("drivers", "Drivers"),
    ("boot", "Boot"),
    ("finalize", "Finalize"),
]


def _bool_label(value: bool) -> str:
    return "Yes" if value else "No"


def _package_group_detail(group_key: str) -> str:
    details = {
        "core-system": "Installs the core command-line foundation used in most Arctyx setups.\nPackages: base-devel, git, curl, wget, ca-certificates, openssh, rsync, unzip, zip, tar, gzip, bzip2, xz, man-db, man-pages",
        "cli-utils": "Adds daily terminal tools for terminal workflow.\nPackages: ripgrep, fd, fzf, bat, eza, tree, jq, yq, htop, btop, ncdu, tmux, neovim, nano, fastfetch",
        "dev-toolchain": "Adds common compilers and language runtimes for development work.\nPackages: gcc, make, cmake, meson, ninja, pkgconf, python, python-pip, nodejs, npm, go, rustup",
        "networking": "Installs connection, DNS, and troubleshooting tools.\nPackages: networkmanager, network-manager-applet, dnsutils, inetutils, nmap, traceroute",
        "desktop-common": "Installs desktop support utilities and file integration tools.\nPackages: xdg-utils, gvfs, gvfs-mtp, gvfs-smb, gvfs-afc, gvfs-gphoto2, gvfs-nfs, file-roller, p7zip, unarchiver",
    }
    return details.get(group_key, "")


def _shell_detail(choice: str) -> str:
    details = {
        "bash": "Keeps the classic Bash workflow.\nPackages: no extra shell package required in most cases; Arctyx mainly keeps Bash as the configured shell.",
        "fish": "Installs and configures Fish.\nPackages: fish",
        "oh-my-zsh": "Installs Zsh, then sets up Oh My Zsh on top of it.\nPackages: zsh\nAlso sets up: oh-my-zsh framework in the target user's home directory.",
    }
    return details.get(choice, "")


def _aur_helper_detail(choice: str) -> str:
    details = {
        "yay": "Installs the Yay AUR helper.\nPackages: yay",
        "paru": "Installs the Paru AUR helper.\nPackages: paru",
        "skip": "Skips AUR helper installation.\nPackages: none",
    }
    return details.get(choice, "")


def _app_item_detail(category_key: str, value: str, label: str) -> str:
    if category_key == "custom":
        return "Custom package names you type here will be installed exactly as entered."
    description_map = {
        "thunar": "Fast and lightweight GTK file manager. Great if you want a simple, reliable file browsing experience without extra desktop overhead.",
        "nautilus": "GNOME's polished file manager with clean defaults, cloud/network integration, and a familiar modern workflow.",
        "dolphin": "Feature-rich KDE file manager with split view, tabs, service menus, and strong power-user tooling.",
        "pcmanfm": "Very lightweight file manager that fits well in minimal or low-resource desktop setups.",
        "nemo": "Cinnamon's practical file manager with a classic layout and easy day-to-day file operations.",
        "krusader": "Twin-panel power-user file manager made for heavy copy, sync, archive, and admin-style file work.",
        "ranger": "Keyboard-driven terminal file manager for people who want fast navigation directly inside the shell.",
        "yazi": "Modern terminal file manager with fast performance, previews, and a more polished CLI experience.",
        "kitty": "GPU-accelerated terminal emulator with strong performance, ligature support, and advanced features.",
        "alacritty": "Minimal, fast GPU terminal focused on speed and simplicity.",
        "wezterm": "Feature-packed modern terminal with tabs, multiplexing, and good cross-platform polish.",
        "foot": "Small and fast Wayland-native terminal that fits nicely in lightweight setups.",
        "ghostty": "Modern terminal focused on speed, clean visuals, and a pleasant default experience.",
        "code": "Microsoft VS Code with a huge extension ecosystem and familiar developer workflow.",
        "codium": "Community-built VS Code variant without Microsoft's branded distribution.",
        "cursor": "AI-focused editor built around a VS Code-like workflow.",
        "zed": "Fast collaborative code editor with a modern UI and low-latency feel.",
        "neovim": "Keyboard-first modal editor that fits terminal-centric and highly customizable workflows.",
        "emacs": "Deeply extensible editor for people who want an all-in-one programmable environment.",
        "lazygit": "Friendly terminal UI for Git that makes commits, staging, rebasing, and branching much easier.",
        "gitui": "Fast terminal Git interface with a focused, keyboard-driven workflow.",
        "helix": "Modern modal editor with batteries-included defaults and a smoother onboarding than classic Vim-style setups.",
        "sublime-text": "Lightweight code editor known for speed and a clean editing experience.",
        "jetbrains-toolbox": "JetBrains launcher that helps install and manage the JetBrains IDE suite.",
        "meld": "Simple visual diff and merge tool that is great for comparing files and folders.",
        "docker-desktop": "Desktop-oriented Docker environment for managing containers with a GUI workflow.",
        "firefox": "Balanced browser with good privacy, extension support, and strong Linux compatibility.",
        "chromium": "Open-source Chromium browser with broad site compatibility.",
        "chrome": "Google Chrome for users who need maximum web compatibility or Google ecosystem integration.",
        "brave": "Chromium-based browser with privacy-oriented defaults and built-in ad/tracker blocking.",
        "waterfox": "Firefox-based browser aimed at users who want classic flexibility and customization.",
        "zen": "A more opinionated, polished Firefox-based browser experience.",
        "librewolf": "Firefox-derived browser focused more heavily on privacy and hardened defaults.",
        "floorp": "Feature-rich Firefox-based browser with extra customization and workspace-style features.",
        "qutebrowser": "Keyboard-driven browser made for users who prefer Vim-like browsing.",
        "vivaldi": "Highly customizable Chromium-based browser with many built-in productivity tools.",
        "vlc": "Flexible media player that opens almost anything and works well as a universal default.",
        "mpv": "Minimal but powerful media player popular with advanced users and scriptable workflows.",
        "gimp": "Raster image editor for photo editing, compositing, and graphics work.",
        "krita": "Digital painting and illustration app that is especially strong for artists and drawing tablets.",
        "inkscape": "Vector graphics editor for logos, icons, diagrams, and SVG work.",
        "darktable": "RAW photo workflow and editing suite for photographers.",
        "kdenlive": "Full-featured video editor with a mature Linux workflow.",
        "shotcut": "Non-linear video editor with a practical feature set and straightforward workflow.",
        "davinci-resolve": "High-end video editing, color, and finishing suite used in more professional workflows.",
        "obs-studio": "Streaming and recording tool for screen capture, live content, and creator workflows.",
        "blender": "3D creation suite for modeling, animation, simulation, and rendering.",
        "audacity": "Simple audio editor for recording, trimming, and cleaning sound.",
        "handbrake": "Video transcoder for converting files into more portable or compressed formats.",
        "telegram-desktop": "Desktop Telegram client for personal and group messaging.",
        "signal-desktop": "Privacy-focused encrypted messaging app tied to the Signal ecosystem.",
        "element-desktop": "Matrix-based messaging client for personal, community, and team chat with strong open-protocol flexibility.",
        "vesktop": "Discord-style client with quality-of-life improvements and community-focused features.",
        "slack-desktop": "Slack desktop client for work chat and team collaboration.",
        "ferdium": "Unified messaging hub that combines multiple chat and communication services in one app.",
        "zoom": "Video meeting client for calls, screen sharing, classes, and remote collaboration.",
        "thunderbird": "Mature email client with calendar, multi-account, and offline mail support.",
        "localsend": "Cross-platform local file sharing app for sending files directly between devices on the same network without cloud upload.",
        "balena-etcher": "Simple USB and SD card image writer that makes flashing ISO or IMG files much easier and safer for everyday use.",
        "ventoy": "Bootable USB utility that lets you copy multiple ISO files onto one drive and boot them directly without reflashing every time.",
        "freedownloadmanager": "Flexible download manager with pause/resume, queue handling, torrent support, and a more polished GUI for large downloads.",
        "ab-download-manager": "Modern download manager with segmented downloads, a clean interface, and a workflow that feels familiar to IDM-style users.",
        "xdman": "Download accelerator with browser integration and segmented downloading that is useful for grabbing large files faster and more reliably.",
        "gparted": "Partition editor for creating, deleting, resizing, and organizing disks visually.",
        "baobab": "Disk usage analyzer that helps you quickly find what is taking up space on the system.",
        "filezilla": "Graphical FTP and SFTP client for moving files to remote servers and shared hosts.",
        "syncthing": "Peer-to-peer sync tool for keeping folders in sync across your own devices without relying on a central cloud provider.",
        "kdeconnect": "Desktop-to-phone integration tool for notifications, clipboard sharing, file transfer, and remote control features.",
        "keepassxc": "Offline password manager for securely storing logins, notes, and secrets in an encrypted vault.",
        "flameshot": "Screenshot utility with annotation tools for quick captures, markups, and sharing.",
        "remmina": "Remote desktop client for SSH, RDP, and VNC connections to other systems.",
        "qbittorrent": "Torrent client with a clean interface for downloading Linux ISOs and other large files.",
        "timeshift": "System snapshot tool for creating restore points before risky system changes.",
        "flatseal": "Flatpak permission manager that makes it easy to inspect and adjust app sandbox permissions.",
        "spotify": "Official Spotify client for streaming music and podcasts.",
        "strawberry": "Clean music player and local library manager for people with downloaded music collections.",
        "amberol": "Very simple music player focused on just opening and enjoying audio quickly.",
        "cmus": "Fast terminal music player for keyboard-first audio workflows.",
        "easyeffects": "Audio effects processor for PipeWire setups, useful for EQ, noise reduction, and mic cleanup.",
        "pavucontrol": "Essential PulseAudio/PipeWire volume control panel for input/output device management.",
        "steam": "Primary Linux gaming platform for native and Proton-powered Windows games.",
        "wine": "Compatibility layer for running many Windows apps and games on Linux.",
        "lutris": "Game launcher/manager that helps organize Wine, emulators, and other gaming runtimes.",
        "gamemode": "Performance tuning helper that optimizes the system while games are running.",
        "mangohud": "In-game performance overlay for FPS, frametimes, and hardware metrics.",
        "heroic": "Launcher for Epic, GOG, and other non-Steam libraries with a nice desktop interface.",
        "prismlauncher": "Popular Minecraft launcher with strong modpack and multi-instance support.",
        "bottles": "Friendly Wine manager for setting up Windows apps and games in isolated containers.",
        "discord": "Voice, text, and community chat app widely used in gaming and hobby communities.",
        "goverlay": "GUI helper for configuring MangoHud and vkBasalt-style gaming overlays.",
        "okular": "Feature-rich document viewer with strong PDF support, annotations, and multipage navigation.",
        "evince": "Simple GNOME document viewer for PDFs and common document formats.",
        "zathura": "Minimal keyboard-friendly PDF/document viewer favored by tiling WM users.",
        "calibre": "E-book manager and reader for organizing libraries, syncing devices, and converting formats.",
        "foliate": "Modern ebook reader with a cleaner reading-focused interface.",
        "papers": "GNOME's newer document viewer for PDFs and other reading workflows.",
        "libreoffice-fresh": "Full office suite for documents, spreadsheets, presentations, and general productivity.",
        "onlyoffice-bin": "Office suite with strong Microsoft Office document compatibility.",
        "obsidian": "Markdown knowledge-base and note-taking app built around linked notes.",
        "joplin": "Open note-taking app with sync support, markdown editing, and to-do organization.",
    }
    package_map = {
        "thunar": "Repo: thunar",
        "nautilus": "Repo: nautilus",
        "dolphin": "Repo: dolphin",
        "pcmanfm": "Repo: pcmanfm",
        "nemo": "Repo: nemo",
        "krusader": "Repo: krusader",
        "ranger": "Repo: ranger",
        "yazi": "Repo: yazi",
        "kitty": "Repo: kitty",
        "alacritty": "Repo: alacritty",
        "wezterm": "Repo: wezterm",
        "foot": "Repo: foot",
        "ghostty": "Repo: ghostty",
        "code": "Repo: code",
        "codium": "AUR: vscodium-bin",
        "cursor": "AUR: cursor-bin",
        "zed": "Repo: zed",
        "neovim": "Repo: neovim",
        "emacs": "Repo: emacs",
        "lazygit": "Repo: lazygit",
        "gitui": "Repo: gitui",
        "helix": "Repo: helix",
        "sublime-text": "AUR: sublime-text-4",
        "jetbrains-toolbox": "AUR: jetbrains-toolbox",
        "meld": "Repo: meld",
        "docker-desktop": "AUR: docker-desktop",
        "firefox": "Repo: firefox",
        "chromium": "Repo: chromium",
        "chrome": "AUR: google-chrome",
        "brave": "AUR: brave-bin",
        "waterfox": "AUR: waterfox-bin",
        "zen": "AUR: zen-browser-bin",
        "librewolf": "AUR: librewolf-bin",
        "floorp": "AUR: floorp-bin",
        "qutebrowser": "Repo: qutebrowser",
        "vivaldi": "Repo: vivaldi",
        "vlc": "Repo: vlc",
        "mpv": "Repo: mpv",
        "gimp": "Repo: gimp",
        "krita": "Repo: krita",
        "inkscape": "Repo: inkscape",
        "darktable": "Repo: darktable",
        "kdenlive": "Repo: kdenlive",
        "shotcut": "AUR: shotcut-bin",
        "davinci-resolve": "AUR: davinci-resolve",
        "obs-studio": "Repo: obs-studio",
        "blender": "Repo: blender",
        "audacity": "Repo: audacity",
        "handbrake": "Repo: handbrake",
        "telegram-desktop": "Repo: telegram-desktop",
        "signal-desktop": "Repo: signal-desktop",
        "element-desktop": "Repo: element-desktop",
        "vesktop": "AUR: vesktop-bin",
        "slack-desktop": "AUR: slack-desktop-wayland",
        "ferdium": "AUR: ferdium-bin",
        "zoom": "AUR: zoom",
        "thunderbird": "Repo: thunderbird",
        "localsend": "AUR: localsend-bin",
        "balena-etcher": "AUR: balena-etcher-bin",
        "ventoy": "AUR: ventoy-bin",
        "freedownloadmanager": "AUR: freedownloadmanager",
        "ab-download-manager": "AUR: ab-download-manager-bin",
        "xdman": "AUR: xdman",
        "gparted": "Repo: gparted",
        "baobab": "Repo: baobab",
        "filezilla": "Repo: filezilla",
        "syncthing": "Repo: syncthing",
        "kdeconnect": "Repo: kdeconnect",
        "keepassxc": "Repo: keepassxc",
        "flameshot": "Repo: flameshot",
        "remmina": "Repo: remmina",
        "qbittorrent": "Repo: qbittorrent",
        "timeshift": "Repo: timeshift",
        "flatseal": "Repo: flatseal",
        "spotify": "AUR: spotify",
        "strawberry": "Repo: strawberry",
        "amberol": "Repo: amberol",
        "cmus": "Repo: cmus",
        "easyeffects": "Repo: easyeffects",
        "pavucontrol": "Repo: pavucontrol",
        "steam": "Repo: steam",
        "wine": "Repo: wine",
        "lutris": "Repo: lutris",
        "gamemode": "Repo: gamemode",
        "mangohud": "Repo: mangohud",
        "heroic": "AUR: heroic-games-launcher-bin",
        "prismlauncher": "Repo: prismlauncher",
        "bottles": "AUR: bottles",
        "discord": "Repo: discord",
        "goverlay": "Repo: goverlay",
        "okular": "Repo: okular",
        "evince": "Repo: evince",
        "zathura": "Repo: zathura",
        "calibre": "Repo: calibre",
        "foliate": "Repo: foliate",
        "papers": "Repo: papers",
        "libreoffice-fresh": "Repo: libreoffice-fresh",
        "onlyoffice-bin": "AUR: onlyoffice-bin",
        "obsidian": "Repo: obsidian",
        "joplin": "AUR: joplin-desktop",
    }
    description = description_map.get(value, f"{label} application for this category.")
    package_info = package_map.get(value, value)
    return f"{description}\n\nPackage: {package_info}"


def _app_installed(value: str) -> bool:
    package_map = {
        "pcmanfm": ["pcmanfm"],
        "code": ["code"],
        "codium": ["vscodium-bin", "vscodium"],
        "cursor": ["cursor-bin", "cursor"],
        "jetbrains-toolbox": ["jetbrains-toolbox"],
        "sublime-text": ["sublime-text-4"],
        "chrome": ["google-chrome"],
        "brave": ["brave-bin"],
        "waterfox": ["waterfox-bin"],
        "zen": ["zen-browser-bin"],
        "librewolf": ["librewolf-bin"],
        "floorp": ["floorp-bin"],
        "vivaldi": ["vivaldi"],
        "shotcut": ["shotcut-bin"],
        "davinci-resolve": ["davinci-resolve"],
        "vesktop": ["vesktop-bin", "vesktop"],
        "slack-desktop": ["slack-desktop-wayland", "slack-desktop"],
        "ferdium": ["ferdium-bin", "ferdium"],
        "element-desktop": ["element-desktop"],
        "zoom": ["zoom"],
        "localsend": ["localsend-bin", "localsend"],
        "balena-etcher": ["balena-etcher-bin", "balena-etcher"],
        "ventoy": ["ventoy-bin", "ventoy"],
        "freedownloadmanager": ["freedownloadmanager"],
        "ab-download-manager": ["ab-download-manager-bin", "ab-download-manager", "abdownloadmanager"],
        "xdman": ["xdman"],
        "gparted": ["gparted"],
        "baobab": ["baobab"],
        "filezilla": ["filezilla"],
        "syncthing": ["syncthing"],
        "kdeconnect": ["kdeconnect"],
        "keepassxc": ["keepassxc"],
        "flameshot": ["flameshot"],
        "remmina": ["remmina"],
        "qbittorrent": ["qbittorrent"],
        "timeshift": ["timeshift"],
        "flatseal": ["flatseal"],
        "spotify": ["spotify"],
        "heroic": ["heroic-games-launcher-bin", "heroic-games-launcher"],
        "bottles": ["bottles"],
        "goverlay": ["goverlay"],
        "onlyoffice-bin": ["onlyoffice-bin"],
        "obsidian": ["obsidian"],
        "joplin": ["joplin-desktop"],
    }
    command_map = {
        "code": ["code"],
        "codium": ["codium"],
        "cursor": ["cursor"],
        "zed": ["zeditor", "zed"],
        "neovim": ["nvim"],
        "emacs": ["emacs"],
        "lazygit": ["lazygit"],
        "gitui": ["gitui"],
        "helix": ["hx"],
        "sublime-text": ["subl"],
        "jetbrains-toolbox": ["jetbrains-toolbox"],
        "docker-desktop": ["docker-desktop"],
        "telegram-desktop": ["telegram-desktop"],
        "signal-desktop": ["signal-desktop"],
        "element-desktop": ["element-desktop"],
        "vesktop": ["vesktop"],
        "slack-desktop": ["slack"],
        "ferdium": ["ferdium"],
        "zoom": ["zoom"],
        "localsend": ["localsend"],
        "balena-etcher": ["balena-etcher", "balena-etcher-electron", "etcher"],
        "ventoy": ["ventoy"],
        "freedownloadmanager": ["fdm", "freedownloadmanager"],
        "ab-download-manager": ["abdownloadmanager", "ab-download-manager"],
        "xdman": ["xdman"],
        "gparted": ["gparted"],
        "baobab": ["baobab"],
        "filezilla": ["filezilla"],
        "syncthing": ["syncthing"],
        "kdeconnect": ["kdeconnect-app", "kdeconnect-indicator", "kdeconnect"],
        "keepassxc": ["keepassxc"],
        "flameshot": ["flameshot"],
        "remmina": ["remmina"],
        "qbittorrent": ["qbittorrent"],
        "timeshift": ["timeshift"],
        "flatseal": ["flatseal"],
        "spotify": ["spotify"],
        "cmus": ["cmus"],
        "easyeffects": ["easyeffects"],
        "pavucontrol": ["pavucontrol"],
        "obsidian": ["obsidian"],
    }
    package_candidates = package_map.get(value, [value])
    command_candidates = command_map.get(value, [])
    return any(_pacman_installed(candidate) for candidate in package_candidates) or any(
        _command_available(candidate) for candidate in command_candidates
    )


def _app_status_text(value: str) -> str:
    return "Installed" if _app_installed(value) else "Not Installed"


def _desktop_choice_detail(value: str, label: str) -> str:
    description_map = {
        "hyprland": "Modern Wayland compositor with sharp visuals, animation, and a highly customizable tiling workflow. Great for users who want a sleek, keyboard-driven daily desktop.",
        "sway": "Stable i3-style Wayland compositor for users who want a clean tiling workflow with fewer visual extras and a more conservative feel.",
        "river": "Minimal dynamic Wayland compositor aimed at users who want a small, composable setup they can shape themselves.",
        "wayfire": "Visual Wayland compositor with effects, plugins, and a more desktop-like feel than many strict tilers. Good if you want modern Wayland with some flair.",
        "labwc": "Lightweight Wayland stacking compositor inspired by Openbox. Good for users who want a simple floating window workflow without a heavy full desktop.",
        "niri": "Scrolling Wayland compositor with a more fluid workspace model than classic tilers. Good for users who want a different take on tiling.",
        "plasma": "Feature-rich full desktop with polished settings, good Wayland progress, and a flexible workflow for both casual and power users.",
        "gnome": "Clean, modern full desktop focused on simplicity, integrated apps, and a very cohesive user experience.",
        "xfce": "Lightweight traditional desktop that stays fast and familiar, especially on modest hardware.",
        "cinnamon": "Comfortable traditional desktop layout with a polished out-of-the-box feel and easy onboarding.",
        "mate": "Classic desktop environment that keeps an older GNOME-style workflow alive with low friction.",
        "lxqt": "Very lightweight Qt-based desktop suitable for low-resource systems and minimal full-desktop setups.",
        "budgie": "Simple modern desktop with a balanced panel-and-menu workflow and cleaner visuals than older classic desktops.",
        "deepin": "Highly styled desktop focused on visual polish and an integrated consumer-friendly experience.",
        "pantheon": "Elegant desktop inspired by elementary OS with a clean, curated feel and minimal visual clutter.",
        "i3": "Well-known X11 tiling window manager with a fast keyboard-first workflow and huge community familiarity.",
        "bspwm": "Scriptable binary-space-partitioning tiling manager for users who like highly controlled window layouts.",
        "awesome": "Lua-configurable window manager that can be shaped into anything from minimal tiling to a full custom desktop shell.",
        "openbox": "Very lightweight stacking window manager for users who want a simple X11 base to build on.",
    }
    core_package_map = {
        "hyprland": "hyprland, xdg-desktop-portal-hyprland",
        "sway": "sway, xdg-desktop-portal-wlr",
        "river": "river, xdg-desktop-portal-wlr",
        "wayfire": "wayfire, xdg-desktop-portal-wlr",
        "labwc": "labwc, xdg-desktop-portal-wlr",
        "niri": "niri, xdg-desktop-portal-gnome",
        "plasma": "plasma-desktop",
        "gnome": "gnome-shell, gnome-session",
        "xfce": "xfce4, xfce4-session",
        "cinnamon": "cinnamon",
        "mate": "mate",
        "lxqt": "lxqt",
        "budgie": "budgie-desktop",
        "deepin": "deepin",
        "pantheon": "pantheon-session, gala, wingpanel",
        "i3": "i3-wm, i3status, i3lock, dmenu",
        "bspwm": "bspwm, sxhkd",
        "awesome": "awesome",
        "openbox": "openbox, obconf, tint2",
    }
    additional_package_map = {
        "hyprland": "waybar, wofi, kitty, sddm",
        "sway": "waybar, wofi, foot, sddm",
        "river": "waybar, wofi, foot, sddm",
        "wayfire": "wayfire-plugins-extra, wf-shell, wcm, foot, sddm",
        "labwc": "waybar, wofi, foot, sddm",
        "niri": "waybar, fuzzel, foot, sddm",
        "plasma": "plasma-meta, konsole, dolphin, sddm",
        "gnome": "gnome, gdm",
        "xfce": "xfce4-goodies, lightdm, lightdm-gtk-greeter",
        "cinnamon": "nemo, lightdm, lightdm-gtk-greeter",
        "mate": "mate-extra, lightdm, lightdm-gtk-greeter",
        "lxqt": "sddm",
        "budgie": "gdm",
        "deepin": "deepin-extra, lightdm, lightdm-gtk-greeter",
        "pantheon": "lightdm, lightdm-pantheon-greeter",
        "i3": "picom, feh, rofi, lightdm, lightdm-gtk-greeter",
        "bspwm": "polybar, rofi, picom, lightdm, lightdm-gtk-greeter",
        "awesome": "rofi, picom, lightdm, lightdm-gtk-greeter",
        "openbox": "rofi, picom, lightdm, lightdm-gtk-greeter",
    }
    description = description_map.get(value, f"{label} desktop or window manager session.")
    core_packages = core_package_map.get(value, value)
    additional_packages = additional_package_map.get(value, "None")
    return (
        f"{description}\n\n"
        f"Core Packages: {core_packages}\n\n"
        f"Additional Packages: {additional_packages}"
    )


def _driver_group_detail(group_key: str) -> str:
    details = {
        "gpu": "Graphics drivers and GPU acceleration packages.\nAvailable packages: nvidia-open-dkms, nvidia-open, nvidia-dkms, nvidia, nvidia-utils, nvidia-settings, linux-headers, mesa, vulkan-radeon, lib32-vulkan-radeon, vulkan-intel, lib32-vulkan-intel, intel-media-driver, xf86-video-amdgpu",
        "chipset": "Microcode and platform firmware updates for CPU and chipset support.\nAvailable packages: intel-ucode, amd-ucode, fwupd",
        "network": "Wi-Fi, Bluetooth, and networking stack packages.\nAvailable packages: networkmanager, iwd, wpa_supplicant, bluez, bluez-utils, broadcom-wl-dkms",
        "others": "Extra firmware and supporting hardware packages.\nAvailable packages: linux-firmware, sof-firmware",
    }
    return details.get(group_key, "")


def _detect_installed_kernel_header_pkg() -> str:
    try:
        uname = subprocess.run(["uname", "-r"], capture_output=True, text=True, check=False).stdout.strip()
    except FileNotFoundError:
        uname = ""
    if "-zen" in uname:
        return "linux-zen-headers"
    if "-lts" in uname:
        return "linux-lts-headers"
    if "-hardened" in uname:
        return "linux-hardened-headers"
    return "linux-headers"


def _safe_command_output(command: list[str]) -> str:
    try:
        return subprocess.run(command, capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return ""


def _safe_which(command_name: str) -> bool:
    return shutil.which(command_name) is not None


def _driver_detected_inventory(state: WizardState) -> dict[str, dict[str, Any]]:
    lspci_out = _safe_command_output(["lspci", "-nnk"])
    lsusb_out = _safe_command_output(["lsusb"])
    lscpu_out = _safe_command_output(["lscpu"])

    gpu_lines = [line.strip() for line in lspci_out.splitlines() if any(token in line.lower() for token in ("vga compatible controller", "3d controller", "display controller"))]
    chipset_lines = [line.strip() for line in lspci_out.splitlines() if any(token in line.lower() for token in ("isa bridge", "smbus", "host bridge", "pci bridge"))]
    network_lines = [line.strip() for line in lspci_out.splitlines() if any(token in line.lower() for token in ("ethernet controller", "network controller", "wireless", "bluetooth"))]
    other_lines = [line.strip() for line in lspci_out.splitlines() if any(token in line.lower() for token in ("audio device", "multimedia controller", "raid bus controller", "usb controller"))]

    cpu_vendor = ""
    for line in lscpu_out.splitlines():
        if "Vendor ID:" in line:
            cpu_vendor = line.split(":", 1)[1].strip()
            break

    header_pkg = _detect_installed_kernel_header_pkg()
    inventory: dict[str, dict[str, Any]] = {}

    gpu_items: list[tuple[str, str]] = []
    gpu_texts: list[str] = []
    gpu_joined = "\n".join(gpu_lines)
    if "NVIDIA" in gpu_joined:
        gpu_items.extend([
            ("nvidia-open-dkms", "nvidia-open-dkms"),
            ("nvidia-open", "nvidia-open"),
            ("nvidia-dkms", "nvidia-dkms"),
            ("nvidia", "nvidia"),
            ("nvidia-utils", "nvidia-utils"),
            ("nvidia-settings", "nvidia-settings"),
            (header_pkg, header_pkg),
        ])
        if state.enable_multilib:
            gpu_items.append(("lib32-nvidia-utils", "lib32-nvidia-utils"))
        gpu_texts.append("NVIDIA GPU detected")
    if any(token in gpu_joined for token in ("AMD", "Advanced Micro Devices", "Radeon")):
        gpu_items.extend([
            ("mesa", "mesa"),
            ("vulkan-radeon", "vulkan-radeon"),
            ("xf86-video-amdgpu", "xf86-video-amdgpu"),
        ])
        if state.enable_multilib:
            gpu_items.append(("lib32-vulkan-radeon", "lib32-vulkan-radeon"))
        gpu_texts.append("AMD/Radeon GPU detected")
    if "Intel" in gpu_joined:
        gpu_items.extend([
            ("mesa", "mesa"),
            ("vulkan-intel", "vulkan-intel"),
            ("intel-media-driver", "intel-media-driver"),
        ])
        if state.enable_multilib:
            gpu_items.append(("lib32-vulkan-intel", "lib32-vulkan-intel"))
        gpu_texts.append("Intel GPU detected")
    if gpu_items:
        deduped = []
        seen = set()
        for item in gpu_items:
            if item[0] not in seen:
                deduped.append(item)
                seen.add(item[0])
        inventory["gpu"] = {
            "label": DRIVER_GROUPS["gpu"]["label"],
            "items": deduped,
            "detected": "; ".join(gpu_lines[:3]) if gpu_lines else ", ".join(gpu_texts),
        }

    chipset_items: list[tuple[str, str]] = []
    if cpu_vendor == "GenuineIntel":
        chipset_items.append(("intel-ucode", "intel-ucode"))
    elif cpu_vendor == "AuthenticAMD":
        chipset_items.append(("amd-ucode", "amd-ucode"))
    if chipset_lines or cpu_vendor:
        chipset_items.append(("fwupd", "fwupd"))
    if chipset_items:
        inventory["chipset"] = {
            "label": DRIVER_GROUPS["chipset"]["label"],
            "items": chipset_items,
            "detected": "; ".join(chipset_lines[:2]) if chipset_lines else (cpu_vendor or "CPU vendor detected"),
        }

    network_items: list[tuple[str, str]] = []
    network_joined = "\n".join(network_lines)
    wireless_detected = any(token in network_joined.lower() for token in ("network controller", "wireless"))
    ethernet_detected = "ethernet" in network_joined.lower()
    bluetooth_detected = "bluetooth" in network_joined.lower() or "bluetooth" in lsusb_out.lower()
    broadcom_detected = "broadcom" in network_joined.lower()
    if wireless_detected:
        network_items.extend([
            ("networkmanager", "networkmanager"),
            ("iwd", "iwd"),
            ("wpa_supplicant", "wpa_supplicant"),
        ])
    if ethernet_detected and ("networkmanager", "networkmanager") not in network_items:
        network_items.append(("networkmanager", "networkmanager"))
    if bluetooth_detected:
        network_items.extend([
            ("bluez", "bluez"),
            ("bluez-utils", "bluez-utils"),
        ])
    if broadcom_detected:
        network_items.extend([
            ("broadcom-wl-dkms", "broadcom-wl-dkms"),
            (header_pkg, header_pkg),
        ])
    if network_items:
        deduped = []
        seen = set()
        for item in network_items:
            if item[0] not in seen:
                deduped.append(item)
                seen.add(item[0])
        detected_lines = network_lines[:3]
        if bluetooth_detected and not any("Bluetooth" in line for line in detected_lines):
            detected_lines.append("Bluetooth device detected")
        inventory["network"] = {
            "label": DRIVER_GROUPS["network"]["label"],
            "items": deduped,
            "detected": "; ".join(detected_lines) if detected_lines else "Detected network hardware",
        }

    others_items: list[tuple[str, str]] = []
    if gpu_items or chipset_items or network_items or other_lines:
        others_items.append(("linux-firmware", "linux-firmware"))
    if any(token in "\n".join(other_lines).lower() for token in ("audio device", "multimedia controller")):
        others_items.append(("sof-firmware", "sof-firmware"))
    if others_items:
        inventory["others"] = {
            "label": DRIVER_GROUPS["others"]["label"],
            "items": others_items,
            "detected": "; ".join(other_lines[:3]) if other_lines else "Additional firmware-supporting hardware detected",
        }

    return inventory


def _pacman_installed(package_name: str) -> bool:
    try:
        return subprocess.run(
            ["pacman", "-Q", package_name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode == 0
    except FileNotFoundError:
        return False


def _command_available(command_name: str) -> bool:
    return shutil.which(command_name) is not None


def _session_installed(session_key: str) -> bool:
    command_map = {
        "hyprland": "Hyprland",
        "sway": "sway",
        "river": "river",
        "wayfire": "wayfire",
        "labwc": "labwc",
        "niri": "niri",
        "plasma": "startplasma-wayland",
        "gnome": "gnome-shell",
        "xfce": "startxfce4",
        "cinnamon": "cinnamon-session",
        "mate": "mate-session",
        "lxqt": "startlxqt",
        "budgie": "budgie-desktop",
        "deepin": "startdde",
        "pantheon": "io.elementary.gala",
        "i3": "i3",
        "bspwm": "bspwm",
        "awesome": "awesome",
        "openbox": "openbox-session",
    }
    package_map = {
        "wayfire": "wayfire",
        "labwc": "labwc",
        "plasma": "plasma-desktop",
        "gnome": "gnome-shell",
        "xfce": "xfce4-session",
        "cinnamon": "cinnamon",
        "mate": "mate-session-manager",
        "lxqt": "lxqt-session",
        "budgie": "budgie-desktop",
        "deepin": "deepin-session-shell",
        "pantheon": "pantheon-session",
    }
    return _command_available(command_map.get(session_key, session_key)) or _pacman_installed(package_map.get(session_key, session_key))


def _session_status_text(session_key: str, state: WizardState | None = None, show_detected: bool = False) -> str:
    detected_suffix = ""
    if (
        show_detected
        and state is not None
        and state.detected_autostart_enabled
        and state.detected_autostart_session == session_key
    ):
        detected_suffix = " (Detected)"
    if session_key == "custom":
        return f"Custom Command{detected_suffix}"
    status = "Installed" if _session_installed(session_key) else "Not Installed"
    return f"{status}{detected_suffix}"


def _display_manager_installed(dm_key: str) -> bool:
    command_map = {
        "gdm": "gdm",
        "sddm": "sddm",
        "lightdm": "lightdm",
        "ly": "ly",
    }
    package_map = {
        "gdm": "gdm",
        "sddm": "sddm",
        "lightdm": "lightdm",
        "ly": "ly",
    }
    return _command_available(command_map.get(dm_key, dm_key)) or _pacman_installed(package_map.get(dm_key, dm_key))


def _display_manager_status_text(dm_key: str) -> str:
    return "Installed" if _display_manager_installed(dm_key) else "Not Installed"


def _detected_shell_label(state: WizardState) -> str:
    shell_name = state.detected_shell.rsplit("/", 1)[-1] if "/" in state.detected_shell else state.detected_shell
    if shell_name == "fish":
        return "Fish"
    if shell_name == "bash":
        return "Bash"
    if shell_name == "zsh":
        return "Zsh"
    return shell_name.title() if shell_name else "Unknown"


def _section_status(state: WizardState, section_key: str) -> str:
    if section_key == "user":
        return f"{state.target_user} | Current Shell: {_detected_shell_label(state)}"
    if section_key == "packages":
        return ", ".join(package_category_label(item) for item in state.package_categories) if state.package_categories else "None"
    if section_key == "apps":
        total = len(state.selected_apps) + len(state.selected_ides) + len(state.custom_apps)
        return f"{total} Selected" if total else "None"
    if section_key == "desktop":
        return ", ".join(desktop_label(item) for item in state.desktop_sessions) if state.desktop_sessions else "None"
    if section_key == "login":
        return (
            f"Selected: {login_method_label(state.login_method)} | "
            f"Detected: {login_method_label(state.detected_login_method)}"
        )
    if section_key == "drivers":
        return driver_mode_label(state.driver_mode)
    if section_key == "boot":
        if state.bootloader_action == "replace":
            bootloader_status = bootloader_label(state.bootloader_choice)
        elif state.bootloader_action == "fix":
            bootloader_status = "Fix Current One"
        else:
            bootloader_status = "Keep Current"
        return f"Bootloader {bootloader_status} | OS-Prober {_bool_label(state.boot_os_prober)}"
    if section_key == "finalize":
        return "Review And Apply"
    return ""


def _section_detail(state: WizardState, section_key: str) -> str:
    if section_key == "user":
        return "\n".join([
            f"User: {state.target_user}",
            f"Use Current User: {_bool_label(state.use_current_user)}",
            f"Detected Shell: {state.detected_shell}",
            f"Current Shell: {_detected_shell_label(state)}",
            f"Selected Shell: {shell_label(state.shell_choice)}",
        ])

    if section_key == "packages":
        package_labels = [package_category_label(item) for item in state.package_categories]
        return "\n".join([
            f"Package Categories: {', '.join(package_labels) if package_labels else 'None Yet'}",
            f"Shell Choice: {shell_label(state.shell_choice)}",
            f"AUR Helper: {aur_helper_label(state.aur_helper)}",
            f"Mirror Optimize: {_bool_label(state.optimize_mirrors)} | Multilib: {_bool_label(state.enable_multilib)} | Chaotic AUR: {_bool_label(state.enable_chaotic_aur)}",
        ])

    if section_key == "apps":
        app_parts: list[str] = []
        for category_key, category in APP_CATEGORIES.items():
            if category_key == "custom":
                selected = state.custom_apps
            else:
                selected = []
                for value, _label, kind in category["items"]:
                    if kind == "ide" and value in state.selected_ides:
                        selected.append(app_label(value))
                    elif kind == "app" and value in state.selected_apps:
                        selected.append(app_label(value))
            app_parts.append(f"{category['label']}: {', '.join(selected) if selected else 'None Yet'}")
        return "\n".join(app_parts)

    if section_key == "desktop":
        sessions = [desktop_label(item) for item in state.desktop_sessions]
        return "\n".join([
            f"Desktop Sessions: {', '.join(sessions) if sessions else 'None Yet'}",
            f"Install Profile: {desktop_profile_label(state.desktop_profile)}",
        ])

    if section_key == "login":
        lines = [
            f"Selected Login Method: {login_method_label(state.login_method)}",
            f"Detected Current Method: {login_method_label(state.detected_login_method)}",
            f"Selected Display Manager: {display_manager_label(state.display_manager)}",
            f"Detected Display Manager: {display_manager_label(state.detected_display_manager)}",
            f"Autologin: {_autologin_mode_label(state)} | Autostart: {_autostart_mode_label(state)}",
        ]
        if state.login_method == "tty-autologin":
            lines.extend([
                f"TTY Device: {state.tty_device}",
                _login_autostart_detail(state),
            ])
        return "\n".join(lines)

    if section_key == "drivers":
        selected_groups = [DRIVER_GROUPS[group_key]["label"] for group_key in state.driver_groups if group_key in DRIVER_GROUPS]
        selected_packages = list(state.driver_packages)
        return "\n".join([
            f"Driver Mode: {driver_mode_label(state.driver_mode)}",
            f"Driver Categories: {', '.join(selected_groups) if selected_groups else 'None Yet'}",
            f"Driver Packages: {', '.join(selected_packages) if selected_packages else 'None Yet'}",
        ])

    if section_key == "boot":
        lines = [
            f"Bootloader Action: {bootloader_action_label(state.bootloader_action)}",
            f"Silent Boot: {_bool_label(state.boot_silent)} | OS-Prober: {_bool_label(state.boot_os_prober)}",
            f"Plymouth: {plymouth_action_label(state.boot_plymouth_action)}",
        ]
        if state.bootloader_action == "replace":
            lines.insert(1, f"Replacement Bootloader: {bootloader_label(state.bootloader_choice)}")
        return "\n".join(lines)

    if section_key == "finalize":
        return "\n".join(state.summary_lines())

    return ""


def step_section_menu(ui: WizardUI, state: WizardState) -> str:
    state.sync_target_with_current_user()
    options = [
        (section_key, label, _section_status(state, section_key), "", _section_detail(state, section_key))
        for section_key, label in SECTION_ORDER
    ]
    return ui.ask_menu(
        "Installer",
        options,
        subtitle="Open a section, configure it, then return here until you are ready to apply.",
        footer="▲/▼ Move • ◀ Back • ▶ Open Section • Enter Open Section • Ctrl+C Quit",
    )


def step_user(ui: WizardUI, state: WizardState) -> None:
    choice = ui.ask_yes_no(
        "User Setup",
        f"Use Current Sudo User? ({state.current_user})",
        default=state.use_current_user,
    )
    if choice == BACK:
        return
    state.use_current_user = choice
    if state.use_current_user:
        state.sync_target_with_current_user()
        return

    while True:
        candidate = ui.ask_input("User Setup", "Target Username:", state.target_user or state.current_user)
        if candidate == BACK:
            return
        if not candidate:
            continue
        try:
            pwd.getpwnam(candidate)
        except KeyError:
            ui.show_message("Invalid User", f'User "{candidate}" does not exist.')
            continue
        state.target_user = candidate
        break


def step_packages(ui: WizardUI, state: WizardState) -> None:
    while True:
        package_summary = ", ".join(package_category_label(item) for item in state.package_categories) if state.package_categories else "None"
        choice = ui.ask_menu(
            "Packages",
            [
                ("groups", "Package Groups", package_summary, ""),
                ("mirrors", "Optimize Mirrors", _bool_label(state.optimize_mirrors), "Refresh pacman mirrorlist", "Runs reflector to refresh pacman mirrors for faster and more reliable downloads.\nPackages: reflector"),
                ("multilib", "Enable Multilib", _bool_label(state.enable_multilib), "Needed for 32-bit libraries", "Required by many 32-bit libraries and common apps such as Steam or Wine.\nPackages enabled via repo: lib32-* packages become available"),
                ("chaotic", "Enable Chaotic AUR", _bool_label(state.enable_chaotic_aur), "Extra prebuilt AUR packages", "Adds the Chaotic AUR binary repository so many AUR packages can be installed as prebuilt pacman packages instead of compiling locally.\nPackages/Config: chaotic-keyring, chaotic-mirrorlist, pacman repo block"),
                ("shell", "Shell", shell_label(state.shell_choice), "", _shell_detail(state.shell_choice)),
                ("aur", "AUR Helper", aur_helper_label(state.aur_helper), "", _aur_helper_detail(state.aur_helper)),
                ("done", "Done", "", ""),
            ],
            subtitle="Configure the Base Package Setup",
        )
        if choice == BACK:
            return
        if choice == "done":
            return
        if choice == "groups":
            selected = ui.ask_checkbox(
                "Package Groups",
                [(value, label, _package_group_detail(value)) for value, label, _detail in PACKAGE_CATEGORY_CHOICES],
                state.package_categories,
                subtitle="Select the Package Groups You Want",
            )
            if selected != BACK:
                state.package_categories = selected
        elif choice == "mirrors":
            selected = ui.ask_yes_no("Mirror Optimization", "Optimize pacman mirrors with reflector?", state.optimize_mirrors)
            if selected != BACK:
                state.optimize_mirrors = selected
        elif choice == "multilib":
            selected = ui.ask_yes_no("Multilib Repository", "Enable multilib repository?", state.enable_multilib)
            if selected != BACK:
                state.enable_multilib = selected
        elif choice == "chaotic":
            selected = ui.ask_yes_no("Chaotic AUR", "Enable Chaotic AUR binary repository?", state.enable_chaotic_aur)
            if selected != BACK:
                state.enable_chaotic_aur = selected
        elif choice == "shell":
            selected = ui.ask_radio("Select Shell", SHELL_CHOICES, state.shell_choice)
            if selected != BACK:
                state.shell_choice = selected
        elif choice == "aur":
            selected = ui.ask_radio("AUR Helper", AUR_HELPER_CHOICES, state.aur_helper)
            if selected != BACK:
                state.aur_helper = selected


def _selected_category_values(state: WizardState, category_key: str) -> list[str]:
    if category_key == "custom":
        return list(state.custom_apps)

    selected: list[str] = []
    for value, _label, kind in APP_CATEGORIES[category_key]["items"]:
        if kind == "ide" and value in state.selected_ides:
            selected.append(value)
        elif kind == "app" and value in state.selected_apps:
            selected.append(value)
    return selected


def _apply_category_values(state: WizardState, category_key: str, values: list[str]) -> None:
    if category_key == "custom":
        state.custom_apps = values
        return

    for value, _label, kind in APP_CATEGORIES[category_key]["items"]:
        if kind == "ide":
            if value in values and value not in state.selected_ides:
                state.selected_ides.append(value)
            if value not in values and value in state.selected_ides:
                state.selected_ides.remove(value)
        else:
            if value in values and value not in state.selected_apps:
                state.selected_apps.append(value)
            if value not in values and value in state.selected_apps:
                state.selected_apps.remove(value)


def _custom_package_detail(text: str) -> str:
    packages = [item for item in text.split() if item]
    if not packages:
        return "Custom Packages: None Yet"
    return f"Custom Packages: {', '.join(packages)}"


def _app_category_detail(state: WizardState, category_key: str) -> str:
    category = APP_CATEGORIES[category_key]
    if category_key == "custom":
        if not state.custom_apps:
            return "Custom Packages: None Yet"
        return f"Custom Packages: {', '.join(state.custom_apps)}"

    selected_labels: list[str] = []
    for value, label, kind in category["items"]:
        if kind == "ide" and value in state.selected_ides:
            selected_labels.append(label)
        elif kind == "app" and value in state.selected_apps:
            selected_labels.append(label)

    if not selected_labels:
        return f"{category['label']}: None Yet"
    return f"{category['label']}: {', '.join(selected_labels)}"


def _desktop_sessions_detail(state: WizardState) -> str:
    if not state.desktop_sessions:
        return "Desktop Sessions: None Yet"
    labels = ", ".join(desktop_label(item) for item in state.desktop_sessions)
    if len(state.desktop_sessions) == 1:
        return f"Desktop Sessions: {labels}\n\nArctyx will prepare this session as your selected desktop environment/window manager choice."
    return f"Desktop Sessions: {labels}\n\nArctyx will prepare all selected sessions so you can choose between them after install."


def _desktop_profile_detail(state: WizardState) -> str:
    sessions = [desktop_label(item) for item in state.desktop_sessions]
    selected_sessions = ", ".join(sessions) if sessions else "None Yet"
    if state.desktop_profile == "full":
        return (
            "Full profile adds a more complete desktop experience with extra utilities, helpers, and convenience packages.\n\n"
            f"Desktop Sessions: {selected_sessions}\n\n"
            "Package Scope: install core session packages plus the extra helper packages listed in each session detail."
        )
    return (
        "Core profile keeps the session lean and closer to a minimal base install.\n\n"
        f"Desktop Sessions: {selected_sessions}\n\n"
        "Package Scope: install only the core session packages listed in each session detail."
    )


def _login_method_detail(state: WizardState) -> str:
    if state.login_method == "display-manager":
        return (
            f"Login Method: {login_method_label(state.login_method)} | Display Manager: {display_manager_label(state.display_manager)}\n"
            f"Detected Current Method: {login_method_label(state.detected_login_method)}"
        )
    if state.login_method == "tty-autologin":
        return (
            f"Login Method: {login_method_label(state.login_method)} | TTY Device: {state.tty_device}\n"
            f"Detected Current Method: {login_method_label(state.detected_login_method)}"
        )
    return (
        f"Login Method: {login_method_label(state.login_method)}\n"
        f"Detected Current Method: {login_method_label(state.detected_login_method)}"
    )


def _login_display_manager_detail(state: WizardState) -> str:
    return (
        f"Display Manager: {display_manager_label(state.display_manager)}\n"
        f"Detected Current Display Manager: {display_manager_label(state.detected_display_manager)}"
    )


def _login_autologin_detail(state: WizardState) -> str:
    return f"Autologin: {_bool_label(state.autologin)}"


def _login_tty_device_detail(state: WizardState) -> str:
    return f"TTY Device: {state.tty_device}"


def _login_autostart_detail(state: WizardState) -> str:
    if state.autostart_action == "skip":
        if state.detected_autostart_enabled:
            detected_label = (
                state.detected_autostart_custom_command
                if state.detected_autostart_session == "custom" and state.detected_autostart_custom_command
                else autostart_session_label(state.detected_autostart_session)
            )
            return f"Autostart Action: Skip\nDetected Current Session: {detected_label}"
        return "Autostart Action: Skip\nDetected Current Session: None"
    if state.autostart_action == "off" or not state.autostart_enabled:
        if state.detected_autostart_enabled:
            detected_label = (
                state.detected_autostart_custom_command
                if state.detected_autostart_session == "custom" and state.detected_autostart_custom_command
                else autostart_session_label(state.detected_autostart_session)
            )
            return f"Autostart Action: Off\nDetected Current Session: {detected_label}"
        return "Autostart Action: Off"
    label = autostart_session_label(state.autostart_session)
    if state.autostart_session == "custom" and state.autostart_custom_command:
        return f"Autostart Action: On | Custom Command: {state.autostart_custom_command}"
    return f"Autostart Action: On | Session: {label}"


def _driver_mode_detail(state: WizardState) -> str:
    return f"Driver Mode: {driver_mode_label(state.driver_mode)}"


def _driver_groups_detail(state: WizardState) -> str:
    if not state.driver_groups:
        return "Driver Categories: None Yet"
    labels = [DRIVER_GROUPS[group_key]["label"] for group_key in state.driver_groups if group_key in DRIVER_GROUPS]
    return f"Driver Categories: {', '.join(labels) if labels else 'None Yet'}"


def _driver_group_selection_detail(state: WizardState, group_key: str) -> str:
    group = DRIVER_GROUPS[group_key]
    selected_labels = [label for pkg, label in group["items"] if pkg in state.driver_packages]
    if not selected_labels:
        return f"{group['label']}: None Yet"
    return f"{group['label']}: {', '.join(selected_labels)}"


def _driver_group_detected_detail(inventory: dict[str, dict[str, Any]], group_key: str, state: WizardState) -> str:
    group = inventory[group_key]
    selected_labels = [label for pkg, label in group["items"] if pkg in state.driver_packages]
    lines = [
        f"Detected Hardware: {group['detected']}",
        f"Selected Packages: {', '.join(selected_labels) if selected_labels else 'None Yet'}",
    ]
    return "\n".join(lines)


def _bootloader_action_detail(state: WizardState) -> str:
    details = {
        "keep": "Leave the current bootloader in place and only apply the other boot-related options below.",
        "fix": "Detect the currently installed bootloader and reinstall that same one cleanly when possible.",
        "replace": "Replace the current bootloader with another supported boot path from the list below.",
    }
    return f"Bootloader Action: {bootloader_action_label(state.bootloader_action)}\n\n{details.get(state.bootloader_action, '')}"


def _bootloader_choice_detail(state: WizardState) -> str:
    detail_map = {
        "grub": "Broad compatibility choice that works well for dual-boot and more traditional Linux setups.\n\nPackages: grub, efibootmgr",
        "systemd-boot": "Clean and minimal UEFI boot manager that fits especially well with unified kernel image workflows.\n\nPackages: systemd, efibootmgr",
        "refind": "Graphical boot manager with a nicer menu-driven feel and strong multi-boot friendliness.\n\nPackages: refind, efibootmgr",
        "limine": "Modern bootloader with a newer ecosystem and a best-effort setup path in Arctyx.\n\nPackages: limine",
        "no-bootloader": "Skip a traditional bootloader and create a direct UEFI boot entry instead.\n\nPackages: efibootmgr",
    }
    return f"Replacement Bootloader: {bootloader_label(state.bootloader_choice)}\n\n{detail_map.get(state.bootloader_choice, '')}"


def _boot_bool_detail(label: str, value: bool) -> str:
    return f"{label}: {_bool_label(value)}"


def _effective_autologin(state: WizardState) -> bool:
    return state.login_method == "tty-autologin" or state.autologin


def _autologin_mode_label(state: WizardState) -> str:
    if state.login_method == "tty-autologin":
        return "TTY"
    if state.login_method == "display-manager" and state.display_manager != "none" and state.autologin:
        return "DM"
    return "Off"


def _autostart_mode_label(state: WizardState) -> str:
    if state.login_method != "tty-autologin":
        return "Off"
    if state.autostart_action == "skip":
        if state.detected_autostart_enabled:
            if state.detected_autostart_session == "custom":
                return "Custom (Detected)"
            return f"{autostart_session_label(state.detected_autostart_session)} (Detected)"
        return "Off"
    if state.autostart_action == "off" or not state.autostart_enabled:
        return "Off"
    if state.autostart_session == "custom":
        return "Custom"
    return autostart_session_label(state.autostart_session)


def _boot_plymouth_detail(state: WizardState) -> str:
    detected = "Enabled" if state.detected_plymouth_enabled else "Disabled"
    return f"Plymouth Action: {plymouth_action_label(state.boot_plymouth_action)}\nDetected Status: {detected}"


def step_apps(ui: WizardUI, state: WizardState) -> None:
    while True:
        category_options = []
        for category_key, category in APP_CATEGORIES.items():
            count = state.count_selected_in_category(category_key)
            preview = state.selected_category_preview(category_key)
            detail = _app_category_detail(state, category_key)
            category_options.append(
                (category_key, category["label"], f"Selected: {count}", preview, detail)
            )
        category_options.append(("done", "Done", "", ""))

        choice = ui.ask_menu(
            "Application Categories",
            category_options,
            subtitle="Select a Category, Then Choose Packages Inside It",
            footer="▲/▼ Move • ◀ Back • ▶ Open Category • Enter Open Category • Ctrl+C Quit",
        )
        if choice == BACK:
            return
        if choice == "done":
            return
        if choice == "custom":
            custom = ui.ask_input(
                "Custom Packages",
                "Enter Custom Package Names Separated by Spaces:",
                " ".join(state.custom_apps),
                detail_title="Details",
                detail_resolver=_custom_package_detail,
                footer="Use `aur:pkgname` For AUR • Type Value • ◀ Back • Enter Confirm • Backspace Delete • Ctrl+C Quit",
            )
            if custom != BACK:
                state.custom_apps = [item for item in custom.split() if item]
            continue

        selected = _selected_category_values(state, choice)
        values = ui.ask_checkbox(
            APP_CATEGORIES[choice]["label"],
            [
                (value, label, _app_item_detail(choice, value, label), _app_status_text(value))
                for value, label, _kind in APP_CATEGORIES[choice]["items"]
            ],
            selected,
            subtitle="Toggle packages, then press d when done",
        )
        if values != BACK:
            _apply_category_values(state, choice, values)


def step_desktop(ui: WizardUI, state: WizardState) -> None:
    while True:
        sessions = ", ".join(desktop_label(item) for item in state.desktop_sessions) if state.desktop_sessions else "None"
        choice = ui.ask_menu(
            "Desktop / WM",
            [
                ("sessions", "Desktop Sessions", sessions, "", _desktop_sessions_detail(state)),
                ("profile", "Install Profile", desktop_profile_label(state.desktop_profile), "", _desktop_profile_detail(state)),
                ("done", "Done", "", ""),
            ],
            subtitle="Restore the Old Desktop/WM Section as Nested Menus",
        )
        if choice == BACK:
            return
        if choice == "done":
            return
        if choice == "sessions":
            selected = ui.ask_checkbox(
                "Desktop / WM Choices",
                [(value, label, _desktop_choice_detail(value, label), _session_status_text(value, state)) for value, label in DESKTOP_CHOICES],
                state.desktop_sessions,
                subtitle="Select one or more desktop/window manager sessions",
            )
            if selected != BACK:
                state.desktop_sessions = selected
        elif choice == "profile":
            selected = ui.ask_radio(
                "Installation Mode",
                DESKTOP_PROFILE_CHOICES,
                state.desktop_profile,
            )
            if selected != BACK:
                state.desktop_profile = selected


def step_login(ui: WizardUI, state: WizardState) -> None:
    while True:
        state.sync_target_with_current_user()
        options = [
            (
                "method",
                "Login Method",
                f"{login_method_label(state.login_method)} | {login_method_label(state.detected_login_method)} (Detected)",
                "",
                _login_method_detail(state),
            ),
        ]
        if state.login_method == "display-manager":
            options.append(
                ("display_manager", "Display Manager", display_manager_label(state.display_manager), "", _login_display_manager_detail(state))
            )
            if state.display_manager != "none":
                options.append(
                    ("autologin", "Autologin", _bool_label(state.autologin), "", _login_autologin_detail(state))
                )
        elif state.login_method == "tty-autologin":
            autostart_status = (
                f"Skip | {autostart_session_label(state.detected_autostart_session)} (Detected)" if state.autostart_action == "skip" and state.detected_autostart_enabled
                else "Skip" if state.autostart_action == "skip"
                else "Off" if state.autostart_action == "off" or not state.autostart_enabled
                else f"On | {autostart_session_label(state.autostart_session) if state.autostart_session != 'custom' else 'Custom'}"
            )
            options.extend(
                [
                    ("tty_device", "TTY Device", state.tty_device, "", _login_tty_device_detail(state)),
                    ("autostart", "Autostart", autostart_status, "", _login_autostart_detail(state)),
                ]
            )
        options.append(("done", "Done", "", ""))

        choice = ui.ask_menu(
            "Login Setup",
            options,
            subtitle="Choose Login, Autologin, and Autostart Behavior",
        )
        if choice == BACK:
            return
        if choice == "done":
            return
        if choice == "method":
            previous_method = state.login_method
            previous_display_manager = state.display_manager
            previous_autologin = state.autologin
            selected = ui.ask_radio("Select Login Method", LOGIN_METHOD_CHOICES, state.login_method)
            if selected == BACK:
                continue
            state.login_method = selected
            if selected == "tty-autologin":
                state.autologin = True
                state.display_manager = "none"
            elif selected == "display-manager":
                dm_selected = ui.ask_radio(
                    "Select Display Manager",
                    [(value, label, detail, _display_manager_status_text(value)) for value, label, detail in DISPLAY_MANAGER_CHOICES],
                    state.display_manager if state.display_manager != "none" else (state.detected_display_manager if state.detected_display_manager != "none" else "gdm"),
                )
                if dm_selected == BACK:
                    state.login_method = previous_method
                    state.display_manager = previous_display_manager
                    state.autologin = previous_autologin
                    continue
                state.display_manager = dm_selected
                state.autologin = False
            else:
                state.autologin = False
                state.display_manager = "none"
            if selected == "manual":
                state.autostart_enabled = False
        elif choice == "display_manager":
            if state.login_method != "display-manager":
                ui.show_message("Display Manager", "Display Manager selection is only used with display-manager login.")
            else:
                selected = ui.ask_radio(
                    "Select Display Manager",
                    [(value, label, detail, _display_manager_status_text(value)) for value, label, detail in DISPLAY_MANAGER_CHOICES],
                    state.display_manager if state.display_manager != "none" else "gdm",
                )
                if selected != BACK:
                    state.display_manager = selected
                    if state.login_method == "display-manager":
                        state.autologin = False
        elif choice == "autologin":
            if state.login_method != "display-manager" or state.display_manager == "none":
                ui.show_message("Autologin", "Autologin for display manager mode is only available after selecting a display manager.")
            else:
                selected = ui.ask_yes_no("Autologin", "Enable autologin?", state.autologin)
                if selected != BACK:
                    state.autologin = selected
        elif choice == "tty_device":
            if state.login_method != "tty-autologin":
                ui.show_message("TTY Device", "TTY Device is only used for tty-autologin mode.")
            else:
                selected = ui.ask_input("TTY Device", "TTY Device:", state.tty_device or "tty1")
                if selected != BACK:
                    state.tty_device = selected or "tty1"
        elif choice == "autostart":
            if state.login_method != "tty-autologin":
                ui.show_message("Autostart", "Autostart submenu is only available for tty-autologin.")
            else:
                selected = ui.ask_radio(
                    "Autostart Action",
                    AUTOSTART_ACTION_CHOICES,
                    state.autostart_action,
                )
                if selected == BACK:
                    continue
                state.autostart_action = selected
                if selected == "skip":
                    state.autostart_enabled = False
                    continue
                if selected == "off":
                    state.autostart_enabled = False
                    continue
                state.autostart_enabled = True
                if state.autostart_enabled:
                    autostart_options = [
                        (value, label, _desktop_choice_detail(value, label), _session_status_text(value, state, True))
                        for value, label in DESKTOP_CHOICES
                    ] + [
                        ("custom", "Custom Command", "Runs a custom command after login instead of a predefined desktop session.", _session_status_text("custom", state, True))
                    ]
                    selected_session = ui.ask_radio(
                        "Autostart Session",
                        autostart_options,
                        state.autostart_session,
                    )
                    if selected_session == BACK:
                        continue
                    state.autostart_session = selected_session
                    if selected_session == "custom":
                        custom_command = ui.ask_input(
                            "Custom Autostart Command",
                            "Command:",
                            state.autostart_custom_command,
                        )
                        if custom_command != BACK:
                            state.autostart_custom_command = custom_command
                    else:
                        if _session_installed(selected_session):
                            state.autostart_install_missing = False
                            continue
                        install_missing = ui.ask_yes_no(
                            "Install Missing Session",
                            "Install the selected session if it is missing?",
                            state.autostart_install_missing,
                        )
                        if install_missing == BACK:
                            continue
                        state.autostart_install_missing = install_missing
                        if install_missing:
                            selected_profile = ui.ask_radio(
                                "Session Install Profile",
                                INSTALL_PROFILE_CHOICES,
                                state.autostart_install_profile,
                            )
                            if selected_profile != BACK:
                                state.autostart_install_profile = selected_profile


def step_drivers(ui: WizardUI, state: WizardState) -> None:
    def _open_manual_driver_categories() -> None:
        if not detected_inventory:
            ui.show_message("Driver Categories", "No supported hardware-specific driver groups were detected on this system.")
            return

        visible_packages = {pkg for group in detected_inventory.values() for pkg, _label in group["items"]}
        state.driver_packages = [pkg for pkg in state.driver_packages if pkg in visible_packages]
        state.driver_groups = [group_key for group_key in state.driver_groups if group_key in detected_inventory]

        while True:
            group_options = []
            for group_key, group in detected_inventory.items():
                count = len([pkg for pkg, _label in group["items"] if pkg in state.driver_packages])
                group_options.append((group_key, group["label"], f"Selected: {count}", "", _driver_group_detected_detail(detected_inventory, group_key, state)))
            group_options.append(("done", "Done", "", ""))

            group_choice = ui.ask_menu(
                "Driver Categories",
                group_options,
                subtitle="Only Driver Groups Matching Detected Hardware Are Shown",
            )
            if group_choice == BACK:
                break
            if group_choice == "done":
                break
            group = detected_inventory[group_choice]
            chosen = ui.ask_checkbox(
                f"{group['label']} Driver Packages",
                [(pkg, label, f"Detected Hardware: {group['detected']}\nInstalls package `{pkg}` for the {group['label']} driver group.") for pkg, label in group["items"]],
                [pkg for pkg, _label in group["items"] if pkg in state.driver_packages],
                subtitle="Only Detected-Hardware Driver Packages Are Listed Here",
            )
            if chosen == BACK:
                continue
            state.driver_groups = [g for g in state.driver_groups if g != group_choice]
            if chosen:
                state.driver_groups.append(group_choice)
            for pkg, _label in group["items"]:
                if pkg in chosen and pkg not in state.driver_packages:
                    state.driver_packages.append(pkg)
                if pkg not in chosen and pkg in state.driver_packages:
                    state.driver_packages.remove(pkg)

    while True:
        detected_inventory = _driver_detected_inventory(state)
        choice = ui.ask_menu(
            "Drivers",
            [
                ("mode", "Driver Mode", driver_mode_label(state.driver_mode), "", _driver_mode_detail(state)),
                ("done", "Done", "", ""),
            ],
            subtitle="Choose Auto Mode or Restore the Manual Category/Package Menus",
        )
        if choice == BACK:
            return
        if choice == "done":
            return
        if choice == "mode":
            selected = ui.ask_radio("Driver Installation Type", DRIVER_CHOICES, state.driver_mode)
            if selected == BACK:
                continue
            state.driver_mode = selected
            if selected != "manual":
                state.driver_groups = []
                state.driver_packages = []
            else:
                _open_manual_driver_categories()


def step_boot(ui: WizardUI, state: WizardState) -> None:
    while True:
        options = [
            ("bootloader_action", "Bootloader Action", bootloader_action_label(state.bootloader_action), "", _bootloader_action_detail(state)),
        ]
        if state.bootloader_action == "replace":
            options.append(
                ("bootloader_choice", "Replacement Bootloader", bootloader_label(state.bootloader_choice), "", _bootloader_choice_detail(state))
            )
        options.extend(
            [
                ("silent", "Silent Boot", _bool_label(state.boot_silent), "", _boot_bool_detail("Silent Boot", state.boot_silent)),
                ("os_prober", "OS-Prober", _bool_label(state.boot_os_prober), "Detect Other OS Installs", _boot_bool_detail("OS-Prober", state.boot_os_prober)),
                ("plymouth", "Plymouth", plymouth_action_label(state.boot_plymouth_action), "", _boot_plymouth_detail(state)),
                ("done", "Done", "", ""),
            ]
        )
        choice = ui.ask_menu(
            "Boot",
            options,
            subtitle="Configure Boot Options",
        )
        if choice == BACK:
            return
        if choice == "done":
            return
        if choice == "bootloader_action":
            selected = ui.ask_radio(
                "Bootloader Action",
                BOOTLOADER_ACTION_CHOICES,
                state.bootloader_action,
                subtitle="Keep the current bootloader, clean-install the current one again, or replace it with another.",
            )
            if selected != BACK:
                state.bootloader_action = selected
                state.boot_replace_bootloader = selected == "replace"
        elif choice == "bootloader_choice":
            selected = ui.ask_radio(
                "Replacement Bootloader",
                BOOTLOADER_CHOICES,
                state.bootloader_choice,
                subtitle="Choose the bootloader Arctyx should install when replacing the current one.",
            )
            if selected != BACK:
                state.bootloader_choice = selected
                state.bootloader_action = "replace"
                state.boot_replace_bootloader = True
        if choice == "silent":
            selected = ui.ask_yes_no("Silent Boot", "Enable silent boot flags?", state.boot_silent)
            if selected != BACK:
                state.boot_silent = selected
        elif choice == "os_prober":
            selected = ui.ask_yes_no("OS-Prober", "Enable OS-Prober?", state.boot_os_prober)
            if selected != BACK:
                state.boot_os_prober = selected
        elif choice == "plymouth":
            selected = ui.ask_radio(
                "Plymouth Action",
                PLYMOUTH_CHOICES,
                state.boot_plymouth_action,
            )
            if selected != BACK:
                state.boot_plymouth_action = selected
def step_summary(ui: WizardUI, state: WizardState) -> bool | str:
    report = build_review_report(state)
    return ui.show_review(
        state.summary_lines(),
        report.validations,
        report.warnings,
        report.recommendations,
        report.ready,
    )


def configure_user_section(ui: WizardUI, state: WizardState) -> None:
    step_user(ui, state)


def configure_packages_section(ui: WizardUI, state: WizardState) -> None:
    step_packages(ui, state)


def configure_apps_section(ui: WizardUI, state: WizardState) -> None:
    step_apps(ui, state)


def configure_desktop_section(ui: WizardUI, state: WizardState) -> None:
    step_desktop(ui, state)


def configure_login_section(ui: WizardUI, state: WizardState) -> None:
    step_login(ui, state)


def configure_drivers_section(ui: WizardUI, state: WizardState) -> None:
    step_drivers(ui, state)


def configure_boot_section(ui: WizardUI, state: WizardState) -> None:
    step_boot(ui, state)


def configure_finalize_section(ui: WizardUI, state: WizardState) -> str:
    result = step_summary(ui, state)
    if result is True:
        return "apply"
    if result in {False, BACK}:
        return "back"
    return "cancel"
