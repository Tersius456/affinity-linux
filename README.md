# Affinity Universal Native Linux Suite

An open-source runtime layer, IPC bridge, and desktop integration suite that turns Serif Affinity v3 into a first-class native Linux application across all major distributions (Arch, Fedora, Ubuntu/Debian, openSUSE) and desktop environments (KDE Plasma, GNOME, XFCE).

Inspired by Valve's Proton architecture on SteamOS: **Wine is isolated as an invisible mathematical/GPU runtime engine, while all user interaction is directly bridged to Linux standards.**

---

## ✨ Features

- **Native FreeDesktop Portals:** Replaces the Win32 open/save dialogs with native KDE (Dolphin) and GNOME (Nautilus) file choosers via `xdg-desktop-portal`.
- **FreeDesktop Session D-Bus (`org.serif.Affinity`):** Single-instance file opening, command-line arguments, and clean IPC without spawning duplicate instances.
- **Dynamic Multi-GPU Support:** Auto-detects NVIDIA (Prime offload), AMD (RADV), and Intel (Mesa) Vulkan drivers.
- **Dolphin & Nautilus Thumbnails:** Fast embedded preview extraction for `.afphoto`, `.afdesign`, and `.afpublisher` files.
- **Zero Latency Resizing:** Custom DXVK rendering profiles and KWin compositor exclusion rules eliminate resize smearing, black screens, and CPU spinloops (locked to 144Hz / VSync).
- **System Font & Color Profile Sync:** Dynamically maps Linux desktop fonts (`Noto Sans`, `Inter`, etc.) and links hardware monitor EDID ICC color profiles for 1:1 color accuracy.
- **True Wayland Fullscreen:** `F11` shortcut toggle for borderless native fullscreen.
- **Recent Files Integration:** Native XBEL (`recently-used.xbel`) synchronization for KDE and GNOME application menus.

---

## 📂 Repository Structure

```
affinity-linux/
├── install.sh                  # One-click universal installer
├── run.sh                      # Universal launcher with GPU auto-detection & D-Bus
├── native_portal_chooser.py    # XDG portal file chooser bridge
├── native_file_chooser.sh      # Wine file chooser interceptor
├── affinity_ipc.py             # FreeDesktop D-Bus IPC daemon
├── affinity_thumbnailer.py     # KDE KIO & GNOME Nautilus thumbnailer
├── open_in_dolphin.sh          # Helper to open folders directly in Dolphin/Nautilus
├── plugin/
│   ├── NativePortalPlugin.cs   # C# Harmony plugin source code
│   └── NativePortalPlugin.dll  # Precompiled APL plugin binary
├── desktop/
│   ├── affinity.desktop        # Desktop application launcher
│   ├── affinity.xml            # FreeDesktop MIME type specifications
│   ├── org.serif.Affinity.service # Session D-Bus service declaration
│   ├── affinity-kio.desktop    # KDE KIO thumbnailer specification
│   └── affinity.thumbnailer    # FreeDesktop/GNOME thumbnailer specification
├── systemd/
│   ├── affinity-wineserver.service # Systemd user keepalive daemon
│   └── affinity-ipc.service        # Background IPC session gateway
├── icons/                      # High-resolution SVG application and MIME icons
└── docs/
    └── RAPOR.md                # Comprehensive technical engineering report
```

---

## 🚀 Quick Start & Installation

To install or deploy this suite on any Linux machine:

```bash
git clone https://github.com/Tersius456/affinity-linux.git
cd affinity-linux
chmod +x install.sh
./install.sh
```

The installer runs 8 automated verification steps:
1. Prepares local XDG directory hierarchy (`~/.local/bin`, `~/.local/share/applications`, etc.).
2. Registers the `affinity` command into your `$PATH`.
3. Installs high-resolution SVG icons and updates the MIME database.
4. Registers thumbnailers for Dolphin and Nautilus.
5. Deploys D-Bus session activation and Systemd user services (`affinity-wineserver`, `affinity-ipc`).
6. Maps hardware monitor EDID color profiles and creates autosave bookmarks.
7. Verifies and activates the APL C# plugin.

---

## 🖥️ Usage

- **Launch Affinity:**
  ```bash
  affinity
  ```
- **Open a project file:**
  ```bash
  affinity design.afdesign
  affinity photo.afphoto
  ```
- **Desktop Actions:** Right-click the Affinity desktop icon in your launcher to quickly access:
  - New Document
  - Native File Chooser
  - Open Autosave & Recovery Folder

---

## 📜 License

MIT License. Designed for the Linux creative and open-source community.
