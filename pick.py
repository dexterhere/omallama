#!/usr/bin/python3
"""Open the desktop file chooser (xdg-desktop-portal) for .gguf models; print chosen paths."""
import os
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
token = "llmpick%d" % os.getpid()
path = "/org/freedesktop/portal/desktop/request/%s/%s" % (bus.get_unique_name()[1:].replace(".", "_"), token)
loop = GLib.MainLoop()

def on_response(conn, sender, obj, iface, signal, params):
    code, results = params.unpack()
    if code == 0:
        for uri in results.get("uris", []):
            print(GLib.filename_from_uri(uri)[0], flush=True)
    loop.quit()

bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",
                     path, None, Gio.DBusSignalFlags.NONE, on_response)
start = os.path.expanduser("~/models") if os.path.isdir(os.path.expanduser("~/models")) else os.path.expanduser("~")
opts = {
    "handle_token": GLib.Variant("s", token),
    "multiple": GLib.Variant("b", True),
    "current_folder": GLib.Variant("ay", (start + "\0").encode()),
    "filters": GLib.Variant("a(sa(us))", [("GGUF models", [(0, "*.gguf"), (0, "*.GGUF")])]),
}
bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
              "org.freedesktop.portal.FileChooser", "OpenFile",
              GLib.Variant("(ssa{sv})", ("", "Select a .gguf model", opts)),
              None, Gio.DBusCallFlags.NONE, -1, None)
loop.run()
