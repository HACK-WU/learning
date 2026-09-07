#!/usr/bin/env bash
# 起一个带 exemplar 的 exporter，并让 Prometheus-ex 来抓
set -u
NET=grafana-net

echo "=== 1. 起 exemplar exporter（python:3.11-slim，端口 9900）==="
docker rm -f grafana-exemplar >/dev/null 2>&1
docker run -d --name grafana-exemplar --network $NET -p 9900:9900 \
  -v /mnt/d/projects/learning/grafana/playground/l09_exemplar_exporter.py:/app/exporter.py:ro \
  python:3.11-slim python /app/exporter.py >/dev/null
echo "  grafana-exemplar -> 宿主 9900"

sleep 4
echo "=== 2. 验证它吐出来的内容（应含 traceID 注释）==="
curl -s --max-time 5 http://localhost:9900/metrics 2>/dev/null | grep -E 'traceID|_bucket' | head -6

echo ""
echo "=== 3. 让 grafana-prom-ex 抓它 ==="
cat > /mnt/d/projects/learning/grafana/playground/prometheus-ex.yml <<'EOF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['grafana-node:9100','grafana-node2:9100','grafana-node3:9100']
  - job_name: exemplar-shop
    static_configs:
      - targets: ['grafana-exemplar:9900']
EOF
echo "  已写 prometheus-ex.yml（新增 job=exemplar-shop）"

docker rm -f grafana-prom-ex >/dev/null 2>&1
docker run -d --name grafana-prom-ex --network $NET -p 9202:9090 \
  -v /mnt/d/projects/learning/grafana/playground/prometheus-ex.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 \
  --enable-feature=exemplar-storage \
  --config.file=/etc/prometheus/prometheus.yml >/dev/null
echo "  grafana-prom-ex 已用新配置重启（9202）"

echo ""
echo "=== 4. 等抓取 ==="
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:9202/-/ready" 2>/dev/null)
  [ "$c" = "200" ] && { echo "  Prometheus-ex 就绪（第 $i 次）"; break; }
  sleep 2
done
sleep 8

echo ""
echo "=== 5. 查 exemplar（关键验证）==="
curl -s "http://localhost:9202/api/v1/query_exemplars?query=http_request_duration_seconds_bucket" 2>/dev/null \
  | python3 -c '
import sys,json
d=json.load(sys.stdin)
if d["status"]!="success":
    print("  查询失败",d); sys.exit()
data=d.get("data") or []
print(f"  返回组数 = {len(data)}")
for g in data:
    print(f"    query={g.get(\"query\")}")
    for it in g.get("exemplars",[]):
        print(f"      labels={it.get(\"labels\")} value={it.get(\"value\")} ts={it.get(\"timestamp\")}")
' 2>/dev/null || echo "  解析失败"

echo ""
echo "=== 6. 顺带确认指标本身抓到了 ==="
curl -s "http://localhost:9202/api/v1/query?query=http_request_duration_seconds_count" 2>/dev/null \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d["data"]["result"];print(f"  序列数={len(r)}");[print(f"    {x[\"metric\"]} = {x[\"value\"][1]}") for x in r]' 2>/dev/null || echo "  查询失败"
