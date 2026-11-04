"""Run: python fetch_probe.py   (GODOT, RETROXR_PROJECT override the paths).
AssetFetcher against a deliberately slow HTTP server:
  /steady.bin  600 kB at ~100 kB/s (6 s): longer than stall_sec (2 s), so only a STALL watchdog lets it through
  /stall.bin   50 kB, then nothing: must be given up on (twice: one retry) and come back empty
  /missing.bin 404: answered, so it is asked for ONCE
"""
import os, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))
HITS = {}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        HITS[self.path] = HITS.get(self.path, 0) + 1
        try:
            if self.path == "/steady.bin":
                self.send_response(200); self.send_header("Content-Length", "600000"); self.end_headers()
                for _ in range(60):
                    self.wfile.write(b"x" * 10000); self.wfile.flush(); time.sleep(0.1)
            elif self.path == "/stall.bin":
                self.send_response(200); self.send_header("Content-Length", "600000"); self.end_headers()
                self.wfile.write(b"x" * 50000); self.wfile.flush(); time.sleep(8)
            else:
                self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers()
        except (BrokenPipeError, ConnectionResetError):
            pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
env = dict(os.environ, FETCH_PORT=str(srv.server_address[1]))
out = subprocess.run([GODOT, "--headless", "--path", PROJECT, "--script", "res://mods/xenu.synth_rift/tests/fetch_probe.gd"],
                     env=env, capture_output=True, text=True, timeout=120).stdout
lines = [l for l in out.splitlines() if l.startswith("[probe]") or "[Rift]" in l]
print("\n".join(lines))
def size(name):
    for l in lines:
        if l.startswith(f"[probe] {name} size="):
            return int(l.split("size=")[1].split()[0])
    return None
checks = {
    "a slow download that keeps arriving completes (stall, not total)": size("steady") == 600000,
    "a stalled one is given up on, empty": size("stall") == 0,
    "the stalled one was tried twice": HITS.get("/stall.bin") == 2,
    "the steady one once": HITS.get("/steady.bin") == 1,
    "a 404 is empty and asked for ONCE": size("missing") == 0 and HITS.get("/missing.bin") == 1,
}
for k, v in checks.items():
    print(f"[fetch] CHECK {'ok  ' if v else 'FAIL'} {k}")
sys.exit(0 if all(checks.values()) else 1)
