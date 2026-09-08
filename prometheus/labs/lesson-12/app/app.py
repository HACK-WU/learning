import os
from http.server import BaseHTTPRequestHandler, HTTPServer

N       = int(os.environ.get("N_SERIES", "10000"))
VAL_LEN = int(os.environ.get("VAL_LEN", "12"))
BASE    = os.environ.get("BASE_NAME", "l12_series")

def gen():
    out = [f"# HELP {BASE} synthetic series\n", f"# TYPE {BASE} gauge\n"]
    for i in range(N):
        v = f"{i:08d}".ljust(VAL_LEN, "x")[:VAL_LEN]
        out.append(f'{BASE}{{idx="{v}"}} {i % 97}\n')
    return "".join(out).encode()

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            body = gen()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass

print(f"l12-app ready: N_SERIES={N} VAL_LEN={VAL_LEN} BASE={BASE}", flush=True)
HTTPServer(("0.0.0.0", 8000), H).serve_forever()
