#!/usr/bin/env bash
# VM 课 0 调试二：确认 /api/v1/import/prometheus 的时间戳精度
set -u
BASE="http://localhost:8428"

NOW=$(date +%s)
echo "NOW(sec)=${NOW}"
echo "NOW(ms) =${NOW}000"
echo

echo "=== A. 同一指标分别用「秒」和「毫秒」写入 ==="
curl -s -m 10 -w "sec_precision_http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "ts_probe{mode=\"sec\"} 1 ${NOW}"
curl -s -m 10 -w "ms_precision_http=%{http_code}\n"  -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "ts_probe{mode=\"ms\"} 2 ${NOW}000"
curl -s -m 10 -w "no_ts_http=%{http_code}\n"         -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "ts_probe{mode=\"none\"} 3"

sleep 2

echo
echo "=== B. 用 /api/v1/export 看原始样本的真实时间戳 ==="
curl -s -m 10 --data-urlencode 'match[]=ts_probe' \
  --data-urlencode "start=$((NOW - 3600))" --data-urlencode "end=$((NOW + 3600))" \
  "$BASE/api/v1/export" | head -20

echo
echo "=== C. 瞬时查询 ts_probe ==="
curl -s -m 10 --data-urlencode "query=ts_probe" --data-urlencode "time=${NOW}" "$BASE/api/v1/query"
echo

echo
echo "=== D. 插入行数自监控 ==="
curl -s -m 10 "$BASE/metrics" | grep -E '^vm_rows_inserted_total|^vm_insert_metrics' | head -10

echo
echo "=== E. 容器日志：是否有 future timestamp 相关告警 ==="
docker logs --tail 40 vm-learn 2>&1 | grep -iE 'future|timestamp|too far|outside' | tail -10 || echo "(无相关日志)"

echo
echo "=== F. 不带时间戳写入后立刻查（默认用服务器当前时间）==="
curl -s -m 10 -w "http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary 'now_probe{job="now"} 9'
sleep 2
curl -s -m 10 --data-urlencode "query=now_probe" "$BASE/api/v1/query"
echo
