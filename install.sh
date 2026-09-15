#!/usr/bin/env bash
# ==============================================================================
# Affinity Native Linux Universal Installer & Setup Suite
# Desteklenen Dağıtımlar: Arch/CachyOS, Fedora, Ubuntu/Debian, openSUSE vb.
# Desteklenen Masaüstleri: KDE Plasma, GNOME, XFCE, Cinnamon, MATE, Cosmic
# ==============================================================================

set -e

COLOR_RESET="\033[0m"
COLOR_BOLD="\033[1m"
COLOR_GREEN="\033[32m"
COLOR_BLUE="\033[34m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"

banner() {
    echo -e "${COLOR_BLUE}${COLOR_BOLD}"
    echo "================================================================"
    echo "       Affinity Universal Native Linux Deployment Suite        "
    echo "================================================================"
    echo -e "${COLOR_RESET}"
}

log_info() { echo -e "${COLOR_GREEN}[✓]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $1"; }
log_step() { echo -e "${COLOR_BLUE}[*]${COLOR_RESET} ${COLOR_BOLD}$1${COLOR_RESET}"; }
log_err()  { echo -e "${COLOR_RED}[✗]${COLOR_RESET} $1"; }

banner

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$WINEPREFIX" ]; then if [ -d "$HOME/.affinity/drive_c" ]; then export WINEPREFIX="$HOME/.affinity"; elif [ -d "$HOME/.local/share/affinity-v3/drive_c" ]; then export WINEPREFIX="$HOME/.local/share/affinity-v3"; else export WINEPREFIX="$HOME/.affinity"; fi; fi
AFFINITY_DIR="${WINEPREFIX}/drive_c/Program Files/Affinity/Affinity"
APL_PLUGINS="${AFFINITY_DIR}/apl/plugins"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_APPS="$HOME/.local/share/applications"
LOCAL_ICONS="$HOME/.local/share/icons/hicolor/scalable"
LOCAL_MIME="$HOME/.local/share/mime/packages"
LOCAL_THUMB="$HOME/.local/share/thumbnailers"
LOCAL_DBUS="$HOME/.local/share/dbus-1/services"
SYSTEMD_USER="$HOME/.config/systemd/user"

# ------------------------------------------------------------------------------
# 1. Dizin Yapısının Doğrulanması & Betik Eşleme
# ------------------------------------------------------------------------------
log_step "1/8: Temel dizin yapısı hazırlanıyor..."
mkdir -p "$LOCAL_BIN" "$LOCAL_APPS" "$LOCAL_THUMB" "$LOCAL_DBUS" "$SYSTEMD_USER"
mkdir -p "$LOCAL_ICONS/apps" "$LOCAL_ICONS/mimetypes" "$LOCAL_MIME" "$HOME/.local/share/icons"
mkdir -p "$WINEPREFIX"

# Betikleri WINEPREFIX dizinine eşle
if [ "$BASE_DIR" != "$WINEPREFIX" ]; then
    cp -f "${BASE_DIR}/run.sh" "${WINEPREFIX}/run.sh"
    cp -f "${BASE_DIR}/native_portal_chooser.py" "${WINEPREFIX}/native_portal_chooser.py"
    cp -f "${BASE_DIR}/native_file_chooser.sh" "${WINEPREFIX}/native_file_chooser.sh"
    cp -f "${BASE_DIR}/affinity_ipc.py" "${WINEPREFIX}/affinity_ipc.py"
    cp -f "${BASE_DIR}/affinity_thumbnailer.py" "${WINEPREFIX}/affinity_thumbnailer.py"
    cp -f "${BASE_DIR}/open_in_dolphin.sh" "${WINEPREFIX}/open_in_dolphin.sh"
    chmod +x "${WINEPREFIX}"/*.sh "${WINEPREFIX}"/*.py 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. PATH Ortam Değişkeninin Kontrolü
# ------------------------------------------------------------------------------
log_step "2/8: Komut satırı (PATH) entegrasyonu kontrol ediliyor..."
ln -sf "${WINEPREFIX}/run.sh" "${LOCAL_BIN}/affinity"
chmod +x "${LOCAL_BIN}/affinity"
ln -sf "${WINEPREFIX}/affinity_thumbnailer.py" "${LOCAL_BIN}/affinity_thumbnailer.py"
chmod +x "${LOCAL_BIN}/affinity_thumbnailer.py"

for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$rc" ]; then
        if ! grep -q '\$HOME/\.local/bin' "$rc" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
            log_info "PATH eklendi: $rc"
        fi
    fi
done

# ------------------------------------------------------------------------------
# 3. İkonlar ve MIME İlişkilendirmesi
# ------------------------------------------------------------------------------
log_step "3/8: İkonlar ve dosya ilişkilendirmeleri (MIME) kaydediliyor..."
if [ -f "${BASE_DIR}/icons/affinity.svg" ]; then
    cp -f "${BASE_DIR}/icons/affinity.svg" "$LOCAL_ICONS/apps/affinity.svg"
    cp -f "${BASE_DIR}/icons/affinity.svg" "$HOME/.local/share/icons/affinity.svg"
elif [ -f "$HOME/.local/share/icons/affinity.svg" ]; then
    cp -f "$HOME/.local/share/icons/affinity.svg" "$LOCAL_ICONS/apps/affinity.svg"
fi

for fmt in "application-x-affinity-photo" "application-x-affinity-designer" "application-x-affinity-publisher" "application-x-affinity-template"; do
    if [ -f "$LOCAL_ICONS/apps/affinity.svg" ]; then
        ln -sf "$LOCAL_ICONS/apps/affinity.svg" "$LOCAL_ICONS/mimetypes/${fmt}.svg" 2>/dev/null || true
    fi
done

if [ -f "${BASE_DIR}/desktop/affinity.xml" ]; then
    cp -f "${BASE_DIR}/desktop/affinity.xml" "$LOCAL_MIME/affinity.xml"
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    log_info "MIME veritabanı güncellendi."
fi
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Küçük Resim (Thumbnail) Entegrasyonu
# ------------------------------------------------------------------------------
log_step "4/8: GNOME/KDE önizleme (Thumbnailer) motoru kuruluyor..."
if [ -f "${BASE_DIR}/desktop/affinity.thumbnailer" ]; then
    cp -f "${BASE_DIR}/desktop/affinity.thumbnailer" "$LOCAL_THUMB/affinity.thumbnailer"
fi

mkdir -p "$HOME/.local/share/kio/thumbnails"
if [ -f "${BASE_DIR}/desktop/affinity-kio.desktop" ]; then
    cp -f "${BASE_DIR}/desktop/affinity-kio.desktop" "$HOME/.local/share/kio/thumbnails/affinity.desktop"
fi

# ------------------------------------------------------------------------------
# 5. D-Bus ve Masaüstü Başlatıcı (.desktop)
# ------------------------------------------------------------------------------
log_step "5/8: D-Bus oturum servisi ve masaüstü kısayolları yapılandırılıyor..."
if [ -f "${BASE_DIR}/desktop/org.serif.Affinity.service" ]; then
    cp -f "${BASE_DIR}/desktop/org.serif.Affinity.service" "$LOCAL_DBUS/org.serif.Affinity.service"
fi
if [ -f "${BASE_DIR}/desktop/affinity.desktop" ]; then
    cp -f "${BASE_DIR}/desktop/affinity.desktop" "$LOCAL_APPS/affinity.desktop"
fi

update-desktop-database "$LOCAL_APPS" 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Systemd Kullanıcı Servisleri
# ------------------------------------------------------------------------------
log_step "6/8: Systemd oturum servisleri kuruluyor..."
if [ -f "${BASE_DIR}/systemd/affinity-wineserver.service" ]; then
    cp -f "${BASE_DIR}/systemd/affinity-wineserver.service" "$SYSTEMD_USER/affinity-wineserver.service"
fi
if [ -f "${BASE_DIR}/systemd/affinity-ipc.service" ]; then
    cp -f "${BASE_DIR}/systemd/affinity-ipc.service" "$SYSTEMD_USER/affinity-ipc.service"
fi

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable affinity-wineserver.service 2>/dev/null || true
systemctl --user restart affinity-wineserver.service 2>/dev/null || true
systemctl --user enable affinity-ipc.service 2>/dev/null || true
systemctl --user restart affinity-ipc.service 2>/dev/null || true
log_info "Servisler devrede (wineserver keepalive & D-Bus gateway)."

# ------------------------------------------------------------------------------
# 7. Donanım Renk Profili ve DXVK Optimizasyonu
# ------------------------------------------------------------------------------
log_step "7/8: Monitör EDID renk profili ve DXVK yapılandırması..."
COLOR_DIR="${WINEPREFIX}/drive_c/windows/system32/spool/drivers/color"
mkdir -p "$COLOR_DIR" 2>/dev/null || true
if [ -f "$HOME/.local/share/icc/edid-a24ecdb5d562f1711194a4a5ba9e69e8.icc" ]; then
    ln -sf "$HOME/.local/share/icc/edid-a24ecdb5d562f1711194a4a5ba9e69e8.icc" "$COLOR_DIR/Monitor_EDID.icc" 2>/dev/null || true
fi

# DXVK konfigürasyonu (Anti-Flicker & Sıfır Gecikme)
if [ -d "${AFFINITY_DIR}" ]; then
    cat << 'DXVK_EOF' > "${AFFINITY_DIR}/dxvk.conf"
# DXVK Optimizations for Affinity on Linux
d3d9.deferSurfaceCreation = True
d3d9.shaderModel = 1
d3d9.maxFrameLatency = 1
d3d9.presentInterval = 1
dxgi.syncInterval = 1
d3d9.samplerAnisotropy = 16
dxvk.enableGraphicsPipelineLibrary = True
dxvk.numCompilerThreads = 16
DXVK_EOF
    log_info "DXVK profil dosyası (dxvk.conf) tam optimizasyonla güncellendi."
fi

# Wine Koyu Tema Renkleri (Beyaz Başlık ve Yanıp Sönmeleri Engelleme)
wine reg add "HKCU\Control Panel\Colors" /v "Window" /t REG_SZ /d "40 44 48" /f >/dev/null 2>&1 || true
wine reg add "HKCU\Control Panel\Colors" /v "MenuBar" /t REG_SZ /d "35 38 41" /f >/dev/null 2>&1 || true
wine reg add "HKCU\Control Panel\Colors" /v "ActiveTitle" /t REG_SZ /d "35 38 41" /f >/dev/null 2>&1 || true
wine reg add "HKCU\Control Panel\Colors" /v "InactiveTitle" /t REG_SZ /d "40 44 48" /f >/dev/null 2>&1 || true

# KDE Plasma KWin Optimizasyonları (Boyutlandırma Gecikmesini ve Titremeyi Önleme)
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kwinrc --group "Plugins" --key "kwin4_effect_geometry_changeExcludedWindowClasses" "krunner,yakuake,affinity.exe,Affinity.real.exe,wine" 2>/dev/null || true
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    log_info "KDE KWin pencere optimizasyonları uygulandı."
fi

# Otomatik kurtarma bağları
ln -sfn "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/autosave" "$HOME/.local/share/affinity-autosave" 2>/dev/null || true
ln -sfn "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/backup" "$HOME/.local/share/affinity-backups" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 8. Eklenti Derleme ve Yükleme (NativePortalPlugin)
# ------------------------------------------------------------------------------
log_step "8/8: APL Eklentisi (NativePortalPlugin.dll) kuruluyor..."
if [ -d "${AFFINITY_DIR}" ]; then
    mkdir -p "${APL_PLUGINS}"
    if [ -f "${BASE_DIR}/plugin/NativePortalPlugin.dll" ]; then
        cp -f "${BASE_DIR}/plugin/NativePortalPlugin.dll" "${APL_PLUGINS}/NativePortalPlugin.dll"
        log_info "NativePortalPlugin.dll başarıyla APL eklenti dizinine yüklendi."
    fi
fi

echo ""
echo -e "${COLOR_GREEN}${COLOR_BOLD}Kurulum Başarıyla Tamamlandı!${COLOR_RESET}"
echo "----------------------------------------------------------------"
echo "• Başlatmak için: terminale 'affinity' yazabilir veya menüden açabilirsiniz."
echo "• Dosya açmak için: 'affinity dosya.png' veya Dolphin'de çift tıklayabilirsiniz."
echo "• Durum kontrolü: 'systemctl --user status affinity-ipc.service'"
echo "================================================================"
