import os
from http.server import BaseHTTPRequestHandler, HTTPServer
N       = int(os.environ.get("N_SERIES", "10000"))
VAL_LEN = int(os.environ.get("VAL_LEN", "12"))
LABELS  = int(os.environ.get("LABELS", "1"))

def gen():
    out = ["# HELP l11_series synthetic series\n", "# TYPE l11_series gauge\n"]
    names = [f"l{k}" for k in range(LABELS)]
    for i in range(N):
        vals = ",".join(f'{nm}="{(i + k*1000000):08d}".ljust(0)' for k, nm in enumerate(names))
        # 构造各标签值
        parts = []
        for k, nm in enumerate(names):
            v = f"{i + k*1000000:08d}".ljust(VAL_LEN, "x")[:VAL_LEN]
            parts.append(f'{nm}="{v}"')
        out.append("l11_series{" + ",".join(parts) + f"}} {i % 97}\n")
    return "".join(out).encode()

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            b = gen()
            self.send_response(200)
            self.send_header("Content-Type","text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            try: self.wfile.write(b)
            except (BrokenPipeError, ConnectionResetError): pass
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass

if __name__ == "__main__":
    print(f"l11c-app: N={N} VAL_LEN={VAL_LEN} LABELS={LABELS}", flush=True)
    HTTPServer(("0.0.0.0",8000),H).serve_forever()
