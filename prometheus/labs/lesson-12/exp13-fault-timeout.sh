#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net
P=http://localhost:19501

echo "######################################################"
echo "# 真实故障：抓取超时（timeout 小于实际响应耗时）      #"
echo "# 症状：target 显示 DOWN，lastError=context deadline  #"
echo "######################################################"

# 造一个慢响应 app：sleep 3 秒再返回
mkdir -p $D/slowapp
cat > $D/slowapp/app.py <<'PY'
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            time.sleep(3)                      # 故意慢
            body = b"# HELP slow_metric demo\n# TYPE slow_metric gauge\nslow_metric 1\n"
            self.send_response(200)
            self.send_header("Content-Type","text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self,*a): pass
HTTPServer(("0.0.0.0",8000),H).serve_forever()
PY
cat > $D/slowapp/Dockerfile <<'DF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py .
CMD ["python","-u","app.py"]
DF
docker build -t l12-slow -f $D/slowapp/Dockerfile $D/slowapp 2>&1 | tail -2

# Prometheus：scrape_timeout=1s，但 app 要 3s → 必然超时
mkdir -p $D/cfg2
cat > $D/cfg2/prometheus-slow.yml <<'YML'
global:
  scrape_interval: 5s
  scrape_timeout: 1s
  evaluation_interval: 5s
scrape_configs:
  - job_name: prometheus
    scrape_timeout: 4s
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: slowapp
    static_configs:
      - targets: ["l12-slow:8000"]
YML

docker rm -f l12-slow l12-prom2 2>/dev/null || true
mkdir -p $D/data2
docker run -d --name l12-slow --network $NET l12-slow >/dev/null
docker run -d --name l12-prom2 --network $NET \
  -v $D/cfg2:/cfg:ro -v $D/data2:/prometheus -p 19501:9090 \
  prom/prometheus:v3.14.0 \
  --config.file=/cfg/prometheus-slow.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.enable-admin-api --web.enable-lifecycle >/dev/null

for i in $(seq 1 40); do
  if curl -sf $P/-/ready >/dev/null 2>&1; then echo "ready after ${i}s"; break; fi
  sleep 1
done
sleep 12

echo
echo "===== [症状] target 状态 ====="
curl -s $P/api/v1/targets | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"job={t['labels'].get('job'):10s} health={t['health']:6s} err={t.get('lastError','')}\")"

echo
echo "===== [倒查 1] up 指标怎么说 ====="
curl -s "$P/api/v1/query?query=up" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print(f\"up={r['value'][1]}  job={r['metric'].get('job')}\")"

echo
echo "===== [倒查 2] 抓取耗时 vs 超时阈值 ====="
curl -s "$P/api/v1/query?query=scrape_duration_seconds" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print(f\"duration={r['value'][1]}  job={r['metric'].get('job')}\")"

echo
echo "===== [倒查 3] 配置里 timeout 是多少 ====="
echo "配置: scrape_timeout=1s（slowapp job 继承 global）"
echo "实测: 抓取耗时 ~3s > 1s → 必然超时"
