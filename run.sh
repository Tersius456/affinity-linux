#!/usr/bin/env bash
# ==============================================================================
# Universal Affinity Linux Launcher
# Compatible with all distributions (Arch, Fedora, Ubuntu, Debian, openSUSE)
# and all Desktop Environments (KDE Plasma, GNOME, XFCE, Cinnamon, etc.)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WINEPREFIX="${WINEPREFIX:-$HOME/.affinity}"
export WINEDLLOVERRIDES="opencl="
export WINEDEBUG="-all"

# DXVK Configuration
export DXVK_CONFIG_FILE="${WINEPREFIX}/drive_c/Program Files/Affinity/Affinity/dxvk.conf"

# Synchronous Multithreading / Fast Sync
export WINE_NTSYNC=1
export WINENTSYNC=1
export WINEFSYNC=1
export WINEESYNC=1

# GPU Vendor Auto-Detection (NVIDIA / AMD / Intel)
if command -v nvidia-smi >/dev/null 2>&1 || lspci 2>/dev/null | grep -iE "vga|3d" | grep -qi "nvidia"; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export DXVK_FILTER_DEVICE_NAME="NVIDIA"
elif lspci 2>/dev/null | grep -iE "vga|3d" | grep -qi "amd|radeon"; then
    export AMD_VULKAN_ICD=RADV
    export DRI_PRIME=1
    export DXVK_FILTER_DEVICE_NAME="AMD"
fi

IPC_PORT=47832
WIN_ARGS=()
LINUX_PATHS=()

# Quick action: Open native file picker directly from taskbar/terminal
if [[ "$1" == "--choose" ]]; then
    python3 "${SCRIPT_DIR}/native_portal_chooser.py" open
    if [[ -f "/tmp/affinity_selected.txt" ]]; then
        chosen="$(cat /tmp/affinity_selected.txt)"
        rm -f /tmp/affinity_selected.txt
        if [[ -n "$chosen" ]]; then
            set -- "$chosen"
        else
            exit 0
        fi
    else
        exit 0
    fi
fi

# Path conversion & URL decoding
for arg in "$@"; do
    [[ "$arg" == "--place" ]] && continue

    # Strip file:// URI scheme
    clean_arg="${arg#file://}"
    if [[ "$clean_arg" == *%* ]]; then
        clean_arg="$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$clean_arg" 2>/dev/null || printf '%s' "$clean_arg")"
    fi
    if [[ "$clean_arg" == /* ]]; then
        win_path="Z:${clean_arg//\//\\}"
        LINUX_PATHS+=("$clean_arg")
        WIN_ARGS+=("\"$win_path\"")
    elif [[ -n "$clean_arg" ]]; then
        LINUX_PATHS+=("$clean_arg")
        WIN_ARGS+=("\"$clean_arg\"")
    fi
done

APP_EXE="${WINEPREFIX}/drive_c/Program Files/Affinity/Affinity/Affinity.exe"

# If Affinity is already running, send paths via universal D-Bus (or TCP fallback)
if pgrep -f "Affinity.real.exe" >/dev/null 2>&1; then
    if [[ ${#LINUX_PATHS[@]} -gt 0 ]]; then
        for lpath in "${LINUX_PATHS[@]}"; do
            # 1. Try KDE qdbus6 / qdbus
            if command -v qdbus6 >/dev/null 2>&1; then
                qdbus6 org.serif.Affinity /org/serif/Affinity org.serif.Affinity.OpenFile "$lpath" >/dev/null 2>&1 && continue
            elif command -v qdbus >/dev/null 2>&1; then
                qdbus org.serif.Affinity /org/serif/Affinity org.serif.Affinity.OpenFile "$lpath" >/dev/null 2>&1 && continue
            fi

            # 2. Try GNOME / Freedesktop standard gdbus
            if command -v gdbus >/dev/null 2>&1; then
                gdbus call --session --dest org.serif.Affinity --object-path /org/serif/Affinity --method org.serif.Affinity.OpenFile "$lpath" >/dev/null 2>&1 && continue
            fi

            # 3. Universal Python Socket Fallback
            python3 -c "
import socket, sys
s = socket.socket()
try:
    s.settimeout(2)
    s.connect(('127.0.0.1', $IPC_PORT))
    s.sendall(sys.argv[1].encode() + b'\n')
    s.shutdown(socket.SHUT_WR)
    s.recv(16)
except Exception:
    pass
finally:
    s.close()
" "$lpath" 2>/dev/null
        done
    fi
    exit 0
fi

# Dynamic Font Synchronization (Automatically maps Wine UI fonts to active Linux system font)
LINUX_FONT="$(fc-match sans-serif -f "%{family}" 2>/dev/null)"
if [[ -n "$LINUX_FONT" ]]; then
    LAST_FONT="$(cat "$WINEPREFIX/.last_font" 2>/dev/null)"
    if [[ "$LINUX_FONT" != "$LAST_FONT" ]]; then
        wine reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Segoe UI" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        wine reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Segoe UI Variable" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        wine reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "Tahoma" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        wine reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "MS Shell Dlg" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        wine reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" /v "MS Shell Dlg 2" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        wine reg add "HKCU\Software\Wine\Fonts\Replacements" /v "Segoe UI" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        wine reg add "HKCU\Software\Wine\Fonts\Replacements" /v "Tahoma" /t REG_SZ /d "$LINUX_FONT" /f >/dev/null 2>&1
        echo "$LINUX_FONT" > "$WINEPREFIX/.last_font"
    fi
fi

# Launch with GameMode if available for maximum Linux CPU/GPU scheduling priority
if command -v gamemoderun >/dev/null 2>&1; then
    exec gamemoderun wine "$APP_EXE" "${WIN_ARGS[@]}"
else
    exec wine "$APP_EXE" "${WIN_ARGS[@]}"
fi
