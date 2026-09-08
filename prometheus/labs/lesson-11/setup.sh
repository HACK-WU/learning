#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet                       # 注意：l11net 已被其他课程容器占用，改用 l11cnet
docker network create $NET 2>/dev/null || true

mkdir -p $D/app

# 不用 prometheus_client：手写文本格式 + 流式生成，app 侧内存恒定
cat > $D/app/app.py <<'PY'
import os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

N       = int(os.environ.get("N_SERIES", "10000"))
VAL_LEN = int(os.environ.get("VAL_LEN", "12"))

def gen():
    out = []
    out.append("# HELP l11_series synthetic series for capacity measurement\n")
    out.append("# TYPE l11_series gauge\n")
    for i in range(N):
        v = f"{i:08d}".ljust(VAL_LEN, "x")[:VAL_LEN]
        out.append(f'l11_series{{idx="{v}"}} {i % 97}\n')
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

if __name__ == "__main__":
    print(f"l11-app ready: N_SERIES={N} VAL_LEN={VAL_LEN}", flush=True)
    HTTPServer(("0.0.0.0", 8000), H).serve_forever()
PY

cat > $D/app/Dockerfile <<'DF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py .
CMD ["python","-u","app.py"]
DF

docker build -t l11c-app -f $D/app/Dockerfile $D/app 2>&1 | tail -3
echo "l11c-app image ready (no prometheus_client dependency)"
