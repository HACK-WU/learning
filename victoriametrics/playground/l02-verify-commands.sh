#!/usr/bin/env bash
# 课 2 命令验证（输出精简版）：每条讲义里出现的命令，按顺序真跑一遍
set -u
BASE="http://localhost:8428"

echo "[1] version"
docker exec vm-learn /victoria-metrics-prod --version 2>&1 | head -1

echo
echo "[2] /health"
curl -s -m 10 "$BASE/health"

echo
echo "[3] 写入一条（不带时间戳）"
curl -s -m 10 -w " http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary 'lesson2_demo{job="l2",host="h1"} 1'

echo
echo "[4] 立刻查（预期：可能为空 —— 这就是课 2 的悬念）"
curl -s -m 10 --data-urlencode 'query=lesson2_demo' "$BASE/api/v1/query" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin)["data"]["result"];print(f"  命中 {len(d)} 条")'

echo
echo "[5] 调 force_flush"
curl -s -m 10 -o /dev/null -w " force_flush http=%{http_code}\n" "$BASE/internal/force_flush"
sleep 2

echo
echo "[6] 刷盘后再查"
curl -s -m 10 --data-urlencode 'query=lesson2_demo' "$BASE/api/v1/query" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin)["data"]["result"];print(f"  命中 {len(d)} 条")'

echo
echo "[7] 加 nocache=1 查询"
curl -s -m 10 --data-urlencode 'query=lesson2_demo' --data-urlencode 'nocache=1' "$BASE/api/v1/query" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin)["data"]["result"];print(f"  命中 {len(d)} 条")'

echo
echo "[8] series/count（刷盘后）"
curl -s -m 10 "$BASE/api/v1/series/count" | python3 -c 'import sys,json;print("  "+str(json.load(sys.stdin)))'

echo
echo "[9] vmui 可达性"
curl -s -o /dev/null -w "  vmui http=%{http_code}\n" -m 10 "$BASE/vmui/"

echo
echo "[10] 自监控关键指标（前 5 行）"
curl -s -m 10 "$BASE/metrics" | grep -E '^vm_' | head -5
