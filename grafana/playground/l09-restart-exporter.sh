#!/usr/bin/env bash
set -u
echo "=== 1. 重启 exporter（加载修正后的脚本）==="
docker restart grafana-exemplar >/dev/null 2>&1
sleep 5

echo ""
echo "=== 2. 看它现在吐什么 ==="
curl -s --max-time 5 http://localhost:9900/metrics 2>/dev/null | grep -E 'bucket|traceID'

echo ""
echo "=== 3. 等 Prometheus 抓一轮（scrape_interval=5s）==="
sleep 15

echo ""
echo "=== 4. target 健康 ==="
curl -s --max-time 5 "http://localhost:9202/api/v1/targets" 2>/dev/null > /tmp/tg3.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/tg3.json"))
for t in d["data"]["activeTargets"]:
    print(f"  job={t['labels'].get('job'):16} {t['labels'].get('instance'):26} health={t['health']}  err={t.get('lastError','')[:70]}")
PY

echo ""
echo "=== 5. 指标抓到了吗 ==="
curl -s --max-time 5 "http://localhost:9202/api/v1/query?query=http_request_duration_seconds_count" 2>/dev/null | head -c 400
echo ""

echo ""
echo "=== 6. ⭐ exemplar 查到了吗（本课关键）==="
curl -s --max-time 5 "http://localhost:9202/api/v1/query_exemplars?query=http_request_duration_seconds_bucket" 2>/dev/null > /tmp/ex2.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/ex2.json"))
data=d.get("data") or []
print(f"  组数 = {len(data)}")
for g in data:
    for it in g.get("exemplars", [])[:5]:
        print("  ★ labels =", it.get("labels"))
        print("    value  =", it.get("value"))
if not data:
    print("  （仍为空）")
PY
