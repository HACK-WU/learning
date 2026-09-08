#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet

# 支持多标签：LABELS 个标签，每个标签值长 VAL_LEN
docker rm -f l11c-app >/dev/null 2>&1 || true
# 重建 app 镜像（支持多标签）
cat > $D/app/app.py <<'PY'
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
PY
docker build -t l11c-app -f $D/app/Dockerfile $D/app 2>&1 | tail -2

echo "# LABELS|VAL_LEN|numSeries|numLabelPairs|mem_MiB|min|max" | tee $D/results-labels.txt
# 固定 5 万序列，变标签个数（1/3/5）与值长度（12/48）
for cfg in "1 12" "3 12" "5 12" "1 48" "3 48"; do
  set -- $cfg; L=$1; V=$2
  echo "--- LABELS=$L VAL_LEN=$V ---" >&2
  R=$(LABELS=$L bash $D/measure.sh 50000 $V 19451 5)
  echo "$L|$V|$R" | tee -a $D/results-labels.txt
done
