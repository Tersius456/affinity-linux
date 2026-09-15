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
export WINEPREFIX="${WINEPREFIX:-$HOME/.affinity}"
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
# 1. Dizin Yapısının Doğrulanması
# ------------------------------------------------------------------------------
log_step "1/8: Temel dizin yapısı hazırlanıyor..."
mkdir -p "$LOCAL_BIN" "$LOCAL_APPS" "$LOCAL_THUMB" "$LOCAL_DBUS" "$SYSTEMD_USER"
mkdir -p "$LOCAL_ICONS/apps" "$LOCAL_ICONS/mimetypes" "$LOCAL_MIME"

# ------------------------------------------------------------------------------
# 2. PATH Ortam Değişkeninin Kontrolü
# ------------------------------------------------------------------------------
log_step "2/8: Komut satırı (PATH) entegrasyonu kontrol ediliyor..."
ln -sf "${BASE_DIR}/run.sh" "${LOCAL_BIN}/affinity"
chmod +x "${LOCAL_BIN}/affinity"
chmod +x "${BASE_DIR}/affinity_thumbnailer.py"
ln -sf "${BASE_DIR}/affinity_thumbnailer.py" "${LOCAL_BIN}/affinity_thumbnailer.py"

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
if [ -f "$HOME/.local/share/icons/affinity.svg" ]; then
    cp -f "$HOME/.local/share/icons/affinity.svg" "$LOCAL_ICONS/apps/affinity.svg"
fi

# Format ikonları (.afphoto, .afdesign, .afpub)
for fmt in "application-x-affinity-photo" "application-x-affinity-designer" "application-x-affinity-publisher" "application-x-affinity-template"; do
    if [ -f "$HOME/.local/share/icons/affinity.svg" ]; then
        ln -sf "$LOCAL_ICONS/apps/affinity.svg" "$LOCAL_ICONS/mimetypes/${fmt}.svg" 2>/dev/null || true
    fi
done

if [ -f "$HOME/.local/share/mime/packages/affinity.xml" ]; then
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    log_info "MIME veritabanı güncellendi."
fi
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Küçük Resim (Thumbnail) Entegrasyonu
# ------------------------------------------------------------------------------
log_step "4/8: GNOME/KDE önizleme (Thumbnailer) motoru kuruluyor..."
cat << 'EOF' > "$LOCAL_THUMB/affinity.thumbnailer"
[Thumbnailer Entry]
TryExec=affinity_thumbnailer.py
Exec=affinity_thumbnailer.py %i %o %s
MimeType=application/x-affinity-photo;application/x-affinity-designer;application/x-affinity-publisher;application/x-affinity-template;
EOF

mkdir -p "$HOME/.local/share/kio/thumbnails" "$HOME/.local/share/kservices5"
cat << 'EOF' > "$HOME/.local/share/kio/thumbnails/affinity.desktop"
[Desktop Entry]
Type=Service
Name=Affinity Document Thumbnailer
X-KDE-ServiceTypes=ThumbCreator
MimeType=application/x-affinity-photo;application/x-affinity-designer;application/x-affinity-publisher;application/x-affinity-template;
Exec=affinity_thumbnailer.py %i %o %s
X-KDE-Priority=10
EOF

# ------------------------------------------------------------------------------
# 5. D-Bus ve Masaüstü Başlatıcı (.desktop)
# ------------------------------------------------------------------------------
log_step "5/8: D-Bus oturum servisi ve masaüstü kısayolları yapılandırılıyor..."
cat << 'EOF' > "$LOCAL_DBUS/org.serif.Affinity.service"
[D-BUS Service]
Name=org.serif.Affinity
Exec=/usr/bin/env affinity
SystemdService=affinity-ipc.service
EOF

update-desktop-database "$LOCAL_APPS" 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Systemd Kullanıcı Servisleri
# ------------------------------------------------------------------------------
log_step "6/8: Systemd oturum servisleri kuruluyor..."
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable affinity-wineserver.service 2>/dev/null || true
systemctl --user restart affinity-wineserver.service 2>/dev/null || true
systemctl --user enable affinity-ipc.service 2>/dev/null || true
systemctl --user restart affinity-ipc.service 2>/dev/null || true
log_info "Servisler devrede (wineserver keepalive & D-Bus gateway)."

# ------------------------------------------------------------------------------
# 7. Donanım Renk Profili ve Font Eşleme
# ------------------------------------------------------------------------------
log_step "7/8: Monitör EDID renk profili ve sistem fontları bağlanıyor..."
COLOR_DIR="${WINEPREFIX}/drive_c/windows/system32/spool/drivers/color"
mkdir -p "$COLOR_DIR"
if [ -f "$HOME/.local/share/icc/edid-a24ecdb5d562f1711194a4a5ba9e69e8.icc" ]; then
    ln -sf "$HOME/.local/share/icc/edid-a24ecdb5d562f1711194a4a5ba9e69e8.icc" "$COLOR_DIR/Monitor_EDID.icc"
fi

# Otomatik kurtarma bağları
ln -sfn "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/autosave" "$HOME/.local/share/affinity-autosave" 2>/dev/null || true
ln -sfn "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/backup" "$HOME/.local/share/affinity-backups" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 8. Eklenti Derleme Doğrulaması (NativePortalPlugin)
# ------------------------------------------------------------------------------
log_step "8/8: APL Eklentisi (NativePortalPlugin.dll) doğrulanıyor..."
if [ -f "${APL_PLUGINS}/NativePortalPlugin.dll" ]; then
    log_info "NativePortalPlugin.dll mevcut ve aktif."
fi

echo ""
echo -e "${COLOR_GREEN}${COLOR_BOLD}Kurulum Başarıyla Tamamlandı!${COLOR_RESET}"
echo "----------------------------------------------------------------"
echo "• Başlatmak için: terminale 'affinity' yazabilir veya menüden açabilirsiniz."
echo "• Dosya açmak için: 'affinity dosya.png' veya Dolphin'de çift tıklayabilirsiniz."
echo "• Durum kontrolü: 'systemctl --user status affinity-ipc.service'"
echo "================================================================"
