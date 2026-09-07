#!/usr/bin/env bash
set -u
echo "=== 1. 重启 Prometheus-ex 让它加载新 target ==="
docker restart grafana-prom-ex >/dev/null 2>&1
sleep 12

echo ""
echo "=== 2. targets 状态 ==="
curl -s "http://localhost:9202/api/v1/targets" 2>/dev/null \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(f"  {t[\"labels\"][\"job\"]:16} {t[\"labels\"].get(\"instance\",\"\"):26} {t[\"health\"]}") for t in d["data"]["activeTargets"]]' 2>/dev/null || echo "  读取失败"

echo ""
echo "=== 3. 指标是否抓到 ==="
curl -s "http://localhost:9202/api/v1/query?query=http_request_duration_seconds_count" 2>/dev/null \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d["data"]["result"];print(f"  序列数={len(r)}");[print(f"    {x[\"metric\"]} = {x[\"value\"][1]}") for x in r]' 2>/dev/null || echo "  查询失败"

echo ""
echo "=== 4. exemplar 查询（关键）==="
curl -s "http://localhost:9202/api/v1/query_exemplars?query=http_request_duration_seconds_bucket" 2>/dev/null > /tmp/exem.json
python3 -c '
import json
d=json.load(open("/tmp/exem.json"))
print("  status =", d.get("status"))
data=d.get("data") or []
print("  组数 =", len(data))
for g in data:
    print("    query =", g.get("query"))
    for it in g.get("exemplars", [])[:5]:
        print("      labels =", it.get("labels"))
        print("      value  =", it.get("value"))
' 2>/dev/null || head -c 400 /tmp/exem.json

echo ""
echo "=== 5. 对照：不带 exemplar 的指标（up）查出来应为空 ==="
curl -s "http://localhost:9202/api/v1/query_exemplars?query=up" 2>/dev/null | head -c 200
echo ""
