#!/usr/bin/env bash
set -uo pipefail
NET=l9net
echo "=== 1. vmselect 正确端口与路径 ==="
for p in 8481 8480; do
  printf '   :%s/health -> ' "$p"
  docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' \
    "http://l9-vmselect:$p/health" 2>/dev/null
done

echo
echo "=== 2. vmselect 支持的 API 前缀 ==="
for path in "/prometheus/api/v1/query" "/api/v1/query" "/select/0/prometheus/api/v1/query"; do
  printf '   %-42s -> ' "$path"
  docker run --rm --network $NET curlimages/curl:latest -s -o /dev/null -w '%{http_code}\n' -G \
    --data-urlencode 'query=up' "http://l9-vmselect:8481$path" 2>/dev/null
done

echo
echo "=== 3. vmselect 日志 ==="
docker logs l9-vmselect 2>&1 | tail -6

echo
echo "=== 4. 给 vmselect 灌数据（通过 vminsert）后重测 ==="
# 起一个 prometheus 写到 vminsert
cat > /tmp/prom-vmcluster.yml <<'EOF'
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: app
    static_configs:
      - targets: ["l9-app:8000"]
remote_write:
  - url: http://l9-vminsert:8480/insert/0/prometheus/api/v1/write
EOF
docker rm -f l9-prom-vmc 2>/dev/null || true
docker run -d --name l9-prom-vmc --network $NET \
  -v /tmp/prom-vmcluster.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus >/dev/null
echo "   l9-prom-vmc started (写 vminsert)"
sleep 25

now=$(date +%s); st=$((now-300))
echo -n "   VM-cluster sum = "
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=sum(app_requests_total)' \
  "http://l9-vmselect:8481/prometheus/api/v1/query" 2>/dev/null \
| python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); rs=d['data']['result']
    print(rs[0]['value'][1] if rs else 'N/A(无数据)')
except Exception as e: print('ERR')"
