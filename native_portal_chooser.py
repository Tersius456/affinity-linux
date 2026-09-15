#!/usr/bin/env python3
import os
import sys
import urllib.parse
import signal
import subprocess
import gi

gi.require_version('Gio', '2.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gio, GLib

def notify(title, message):
    try:
        subprocess.Popen([
            'notify-send',
            '-i', os.path.expanduser('~/.local/share/icons/affinity.svg'),
            title,
            message
        ])
    except Exception:
        pass

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'open'
    init_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~')
    if not os.path.isdir(init_dir):
        init_dir = os.path.expanduser('~')

    output_file = "/tmp/affinity_selected.txt"
    done_file = "/tmp/affinity_done.txt"

    for f in [output_file, done_file]:
        if os.path.exists(f):
            try:
                os.remove(f)
            except Exception:
                pass

    loop = GLib.MainLoop()

    def quit_loop(*args):
        if loop.is_running():
            loop.quit()

    signal.signal(signal.SIGINT, quit_loop)
    signal.signal(signal.SIGTERM, quit_loop)

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

        def on_response(conn, sender, path, iface, signal_name, params, user_data):
            try:
                resp_code, results = params.unpack()
                if resp_code == 0:
                    uris = results.get('uris', [])
                    if uris:
                        parsed = urllib.parse.urlparse(uris[0])
                        local_path = urllib.parse.unquote(parsed.path)
                        if local_path and (os.path.exists(local_path) or mode == 'save'):
                            with open(output_file, 'w', encoding='utf-8') as out:
                                out.write(local_path)
                            try:
                                import gi
                                gi.require_version('Gtk', '3.0')
                                from gi.repository import Gtk
                                rm = Gtk.RecentManager.get_default()
                                rm.add_item(GLib.filename_to_uri(os.path.abspath(local_path)))
                            except Exception:
                                pass
                            if mode == 'save':
                                fname = os.path.basename(local_path)
                                notify("Affinity", f"Belge kaydedildi: {fname}")
            except Exception as e:
                sys.stderr.write(f"Error handling response: {e}\n")
            finally:
                quit_loop()

        bus.signal_subscribe(
            'org.freedesktop.portal.Desktop',
            'org.freedesktop.portal.Request',
            'Response',
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_response,
            None
        )

        proxy = Gio.DBusProxy.new_sync(
            bus,
            Gio.DBusProxyFlags.NONE,
            None,
            'org.freedesktop.portal.Desktop',
            '/org/freedesktop/portal/desktop',
            'org.freedesktop.portal.FileChooser',
            None
        )

        title = "Affinity - Dosya Aç" if mode == "open" else "Affinity - Farklı Kaydet"

        options = {
            'modal': GLib.Variant('b', True),
            'multiple': GLib.Variant('b', False),
        }

        # Desteklenen dosya filtreleri
        filters = [
            GLib.Variant('(sa(us))', (
                "Desteklenen Belgeler (*.afphoto, *.afdesign, *.afpub, *.png, *.jpg...)",
                [
                    (0, "*.afphoto"), (0, "*.afdesign"), (0, "*.afpub"),
                    (0, "*.png"), (0, "*.jpg"), (0, "*.jpeg"), (0, "*.svg"),
                    (0, "*.psd"), (0, "*.pdf"), (0, "*.webp"), (0, "*.tiff")
                ]
            )),
            GLib.Variant('(sa(us))', (
                "Affinity Belgeleri (*.afphoto, *.afdesign, *.afpub)",
                [(0, "*.afphoto"), (0, "*.afdesign"), (0, "*.afpub")]
            )),
            GLib.Variant('(sa(us))', (
                "Resim Dosyaları (*.png, *.jpg, *.jpeg, *.svg, *.webp...)",
                [(0, "*.png"), (0, "*.jpg"), (0, "*.jpeg"), (0, "*.svg"), (0, "*.webp"), (0, "*.psd"), (0, "*.tiff")]
            )),
            GLib.Variant('(sa(us))', (
                "Tüm Dosyalar (*)",
                [(0, "*")]
            ))
        ]
        options['filters'] = GLib.Variant('a(sa(us))', filters)

        folder_bytes = (init_dir + '\0').encode('utf-8')
        options['current_folder'] = GLib.Variant('ay', folder_bytes)

        if mode == 'save':
            proxy.SaveFile('(ssa{sv})', "", title, options)
        else:
            proxy.OpenFile('(ssa{sv})', "", title, options)

        loop.run()

    except Exception as ex:
        sys.stderr.write(f"Portal error: {ex}, falling back to zenity\n")
        cmd = ["zenity", "--file-selection", "--title=" + ("Affinity - Dosya Aç" if mode == "open" else "Affinity - Farklı Kaydet")]
        if mode == "save":
            cmd.append("--save")
            cmd.append("--confirm-overwrite")
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            with open(output_file, "w", encoding="utf-8") as out:
                out.write(res.stdout.strip())
            if mode == "save":
                fname = os.path.basename(res.stdout.strip())
                notify("Affinity", f"Belge kaydedildi: {fname}")

    finally:
        with open(done_file, 'w', encoding='utf-8') as df:
            df.write("done\n")

if __name__ == '__main__':
    main()
