#!/usr/bin/env python3
"""
Affinity Native Linux D-Bus & IPC Service
Linux standartlarına tam uyumlu D-Bus oturum servisi:
- org.serif.Affinity ve org.freedesktop.Application arayüzleri
- Dolphin / KDE Son Belgeler (recently-used.xbel) otomatik kaydı
- Geriye dönük uyumluluk için TCP 47832 soketi
"""
import os
import sys
import socket
import threading
import signal
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib, Gio

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
    HAVE_GTK = True
except Exception:
    HAVE_GTK = False

PORT = 47832
QUEUE_FILE = "/tmp/affinity_open_queue.txt"
BUS_NAME = "org.serif.Affinity"
OBJECT_PATH = "/org/serif/Affinity"

def register_recent_file(linux_path):
    """Açılan dosyayı KDE ve FreeDesktop Son Kullanılanlar (recently-used.xbel) listesine kaydet."""
    if not os.path.exists(linux_path):
        return
    try:
        if HAVE_GTK:
            rm = Gtk.RecentManager.get_default()
            uri = GLib.filename_to_uri(os.path.abspath(linux_path))
            rm.add_item(uri)
            print(f"[Recent] KDE son belgelere eklendi: {linux_path}", flush=True)
    except Exception as e:
        print(f"[Recent] Kayıt hatası: {e}", file=sys.stderr)

def queue_file_for_affinity(path_str):
    """Gelen dosya yolunu Wine formatına çevirip kuyruğa ekle."""
    path_str = path_str.strip().strip('"').strip("'")
    if not path_str:
        return

    # file:// URI temizle
    if path_str.startswith("file://"):
        import urllib.parse
        path_str = urllib.parse.unquote(path_str[7:])

    linux_path = path_str
    if path_str.startswith("/"):
        win_path = "Z:" + path_str.replace("/", "\\")
        register_recent_file(linux_path)
    else:
        win_path = path_str

    with open(QUEUE_FILE, "a", encoding="utf-8") as f:
        f.write(win_path + "\n")
    print(f"[IPC] Kuyruğa alındı: {win_path}", flush=True)

class AffinityDBusService(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method("org.serif.Affinity", in_signature="s", out_signature="b")
    def OpenFile(self, path):
        queue_file_for_affinity(str(path))
        return True

    @dbus.service.method("org.serif.Affinity", in_signature="as", out_signature="b")
    def OpenFiles(self, paths):
        for p in paths:
            queue_file_for_affinity(str(p))
        return True

    @dbus.service.method("org.serif.Affinity", in_signature="", out_signature="b")
    def Activate(self):
        print("[DBus] Activate çağrıldı", flush=True)
        return True

    # FreeDesktop Application Standard Interface
    @dbus.service.method("org.freedesktop.Application", in_signature="asa{sv}", out_signature="")
    def Open(self, uris, platform_data):
        for u in uris:
            queue_file_for_affinity(str(u))

    @dbus.service.method("org.freedesktop.Application", in_signature="a{sv}", out_signature="")
    def Activate(self, platform_data):
        print("[DBus] org.freedesktop.Application.Activate çağrıldı", flush=True)

def run_tcp_server():
    """Geriye dönük uyumluluk için TCP soket dinleyicisi."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(10)
    print(f"[TCP] 127.0.0.1:{PORT} dinleniyor...", flush=True)

    while True:
        try:
            conn, _ = srv.accept()
            data = b""
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            for line in data.decode("utf-8", errors="replace").splitlines():
                queue_file_for_affinity(line)
            conn.sendall(b"OK\n")
            conn.close()
        except Exception as e:
            print(f"[TCP] Hata: {e}", flush=True)

def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(BUS_NAME, bus)
    service = AffinityDBusService(bus)
    print(f"[DBus] {BUS_NAME} servisi başlatıldı ({OBJECT_PATH})", flush=True)

    # TCP sunucusunu arka plan iş parçacığında çalıştır
    t = threading.Thread(target=run_tcp_server, daemon=True)
    t.start()

    loop = GLib.MainLoop()

    def stop_service(*args):
        if loop.is_running():
            loop.quit()

    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)

    loop.run()

if __name__ == "__main__":
    main()
