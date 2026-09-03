#!/usr/bin/env bash
# VM 课 0 调试三：样本到底有没有落盘？逐层取证
set -u
BASE="http://localhost:8428"

echo "=== A. 各协议插入行数（完整）==="
curl -s -m 10 "$BASE/metrics" | grep -E '^vm_rows_inserted_total' | grep -v ' 0$'

echo
echo "=== B. 数据目录体积变化（有没有真的写文件）==="
docker exec vm-learn du -sh /victoria-metrics-data/data 2>&1
docker exec vm-learn find /victoria-metrics-data/data -type f | head -20

echo
echo "=== C. 不带任何时间范围导出 ts_probe ==="
curl -s -m 10 --data-urlencode 'match[]=ts_probe' "$BASE/api/v1/export"
echo "(export 结束)"

echo
echo "=== D. 导出全部序列（match[]={__name__!=\"\"}）前 10 行 ==="
curl -s -m 10 --data-urlencode 'match[]={__name__!=""}' "$BASE/api/v1/export" | head -10

echo
echo "=== E. 写入后强制刷新并等待，再查 ==="
curl -s -m 10 -w "flush_http=%{http_code}\n" "$BASE/internal/force_flush" 2>&1 || echo "(force_flush 端点不存在)"
sleep 3
curl -s -m 10 --data-urlencode "query=ts_probe" "$BASE/api/v1/query"
echo

echo
echo "=== F. 检查 -search.lookback-delta / 当前查询默认时间 ==="
docker exec vm-learn /victoria-metrics-prod --help 2>&1 | grep -A2 'lookback-delta' | head -6

echo
echo "=== G. 再写一条并立刻用 export 查（最小复现）==="
NOW=$(date +%s)
curl -s -m 10 -w "write_http=%{http_code}\n" -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "min_probe{job=\"min\"} 5 ${NOW}"
sleep 2
echo "-- export min_probe --"
curl -s -m 10 --data-urlencode 'match[]=min_probe' "$BASE/api/v1/export"
echo "-- query min_probe --"
curl -s -m 10 --data-urlencode "query=min_probe" "$BASE/api/v1/query"
echo
echo "-- rows inserted prometheus --"
curl -s -m 10 "$BASE/metrics" | grep -E '^vm_rows_inserted_total\{type="prometheus"'

echo
echo "=== H. 容器日志最新 15 行 ==="
docker logs --tail 15 vm-learn 2>&1
