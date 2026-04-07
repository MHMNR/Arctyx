<div align="center">
  <img src=".github/assets/banner.png" alt="Arctyx banner" width="100%" />

# Arctyx

**A guided post-install setup tool for Arch Linux**

[![Platform](https://img.shields.io/badge/platform-Arch%20Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/python-3.x-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](#)

*Stop repeating the same Arch setup steps every time. Let Arctyx handle it.*

</div>

---

## What is Arctyx?

Arctyx is a modular, terminal-based setup wizard for Arch Linux. Instead of manually hunting down package names, remembering login configs, or digging through wiki pages after every fresh install — you run Arctyx and it walks you through everything in a clean, guided flow.

It's not a full disk installer. It's the tool you run **after** Arch is booted, when you need to make it actually usable.

---

## What It Configures

| Category | Details |
|---|---|
| **User Setup** | User account configuration |
| **Packages** | Core groups + optional apps by category + custom picks |
| **Desktop** | Desktop environments and window managers |
| **Login** | Login mode, autologin, autostart behavior |
| **Drivers** | Hardware-aware driver selection |
| **Boot** | Bootloader configuration and boot tuning |

---

## Requirements

- Arch Linux or an Arch-based distro
- `bash`
- `python` (3.x)
- `jq`
- Root access (needed for apply, rollback, and uninstall)

---

## Getting Started

### Clone The Repo
```bash
git clone https://github.com/MHMNR/Arctyx.git
```

### Enter The Project Folder
```bash
cd Arctyx
```

### Run The Setup Wizard
```bash
sudo bash setup.sh
```

## Advanced

**Preview what will be applied (dry run):**
```bash
python setup/main.py --action plan --state setup/state/state.json
```

**Apply the configuration directly from saved state:**
```bash
python setup/main.py --action apply --state setup/state/state.json
```

---

## Project Structure

```
arctyx/
├── setup.sh                  # Main launcher — start here
├── setup/
│   ├── main.py               # Python entrypoint
│   ├── ui/                   # Wizard UI and rendering logic
│   ├── backend/              # Bash modules (packages, drivers, login, boot, user)
│   └── state/                # JSON state schema and defaults
└── .github/                  # GitHub templates and repo configs
```

---

## How It Works

Arctyx uses a three-layer architecture to keep things clean and debuggable:

```
[ Python Wizard UI ]  ←  what you interact with
        ↓
[ JSON State File ]   ←  stores your selections
        ↓
[ Bash Backend ]      ←  does the actual system work
```

This separation means the UI never directly touches your system — the backend scripts handle all real changes. Easy to review, easy to extend.

---

## Design Philosophy

- **Guided, not automated** — you stay in control of every decision
- **Modular** — each configuration area is its own backend module
- **State-driven** — your choices are saved before anything is applied
- **Rollback-friendly** — designed to be safe to rerun or undo
- **Arch-focused** — not trying to be a generic cross-distro tool

---

## Who It's For

- Arch users who reinstall or reconfigure systems regularly
- Anyone who wants an installer-like experience without giving up control
- Developers who want a clean, readable system setup codebase they can actually maintain

---

<div align="center">
<sub>Arctyx is a post-install helper for a working Arch installation — not a disk partitioner or live ISO tool.</sub>
</div>
