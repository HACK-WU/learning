#!/usr/bin/env bash
# 课 4 · 4.2 决定性实验：在 Grafana 与 Prometheus 之间放一个「记录型代理」
# 目的：抓到 Grafana 后端真正发出的 HTTP 请求报文（方法 / 路径 / 头 / body）
set -u

WORK=/tmp/l04sniff
rm -rf "$WORK"; mkdir -p "$WORK"

cat > "$WORK/sniff.py" <<'PYEOF'
import http.server, urllib.request, urllib.error, json, sys, os, datetime

UPSTREAM = "http://grafana-prom:9090"
LOG = "/mnt/log/sniff.log"

def log(*a):
    with open(LOG, "a") as f:
        f.write(" ".join(str(x) for x in a) + "\n")

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _handle(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        ts = datetime.datetime.now().isoformat(timespec="milliseconds")

        log("=" * 70)
        log("[%s] %s %s" % (ts, method, self.path))
        log("--- HEADERS ---")
        for k, v in self.headers.items():
            log("  %s: %s" % (k, v))
        if body:
            log("--- BODY (%d bytes) ---" % len(body))
            try:
                log("  " + body.decode("utf-8").replace("\n", "\n  "))
            except Exception:
                log("  <binary>")
        else:
            log("--- BODY --- (empty)")

        # 转发到真实 Prometheus
        url = UPSTREAM + self.path
        r = urllib.request.Request(url, data=body if body else None, method=method)
        for k, v in self.headers.items():
            if k.lower() in ("host", "content-length", "connection",
                             "accept-encoding", "transfer-encoding"):
                continue
            try:
                r.add_header(k, v)
            except Exception:
                pass
        try:
            with urllib.request.urlopen(r, timeout=30) as resp:
                data = resp.read()
                code = resp.status
        except urllib.error.HTTPError as e:
            data = e.read(); code = e.code
        except Exception as e:
            log("!!! 转发失败: %s" % e)
            data = b'{"status":"error"}'; code = 502

        log("--- UPSTREAM RESPONSE --- HTTP %s, %d bytes" % (code, len(data)))
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  self._handle("GET")
    def do_POST(self): self._handle("POST")
    def log_message(self, *a): pass

log("### sniffer 启动 ###")
http.server.HTTPServer(("0.0.0.0", 9099), H).serve_forever()
PYEOF

echo "[1] 清理同名旧容器"
docker rm -f l04-sniff >/dev/null 2>&1

echo "[2] 启动记录型代理（挂卷到 /mnt/log，日志宿主机可见）"
docker run -d --name l04-sniff --network grafana-net \
  -v "$WORK":/mnt/log \
  python:3.11-slim python /mnt/log/sniff.py
sleep 3
docker ps --filter name=l04-sniff --format '  {{.Names}}  {{.Status}}'

echo ""
echo "[3] 建临时数据源指向代理"
curl -s -u admin:admin -X DELETE http://localhost:3001/api/datasources/uid/l04sniff >/dev/null
curl -s -u admin:admin -X POST http://localhost:3001/api/datasources \
  -H 'Content-Type: application/json' \
  -d '{"name":"L04Sniff","uid":"l04sniff","type":"prometheus","access":"proxy",
       "url":"http://l04-sniff:9099","isDefault":false,
       "jsonData":{"httpMethod":"POST","httpHeaderName1":"Accept-Encoding","httpHeaderValue1":"identity"}}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('  创建:',d.get('name'),d.get('uid'))"

echo ""
echo "[4] 通过 Grafana 发一次带变量的查询（触发完整旅程）"
cat > "$WORK/q.json" <<'JSON'
{
  "queries": [{
    "refId": "A",
    "datasource": {"type": "prometheus", "uid": "l04sniff"},
    "expr": "sum(rate(node_cpu_seconds_total{instance=~\"$host\",mode=\"idle\"}[$__rate_interval])) by (instance)",
    "range": true, "instant": false,
    "intervalMs": 15000, "maxDataPoints": 100,
    "legendFormat": "{{instance}}"
  }],
  "from": "now-1h", "to": "now"
}
JSON
curl -s -u admin:admin -X POST http://localhost:3001/api/ds/query \
  -H 'Content-Type: application/json' --data @"$WORK/q.json" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=(d.get('results') or {}).get('A') or {}
print('  HTTP 层 status =', r.get('status'))
frs=r.get('frames') or []
print('  frames =', len(frs))
for f in frs:
    print('    expr:', (f.get('schema',{}).get('meta',{}) or {}).get('executedQueryString','-').split(chr(10))[0])
"

sleep 1
echo ""
echo "=================================================================="
echo " 抓取到的请求报文（Grafana 后端 → Prometheus）"
echo "=================================================================="
cat "$WORK/sniff.log"
echo "=================================================================="

echo ""
echo "[5] 清理"
curl -s -u admin:admin -X DELETE http://localhost:3001/api/datasources/uid/l04sniff >/dev/null
echo "  数据源已删"
docker rm -f l04-sniff >/dev/null 2>&1
echo "  代理容器已删"
