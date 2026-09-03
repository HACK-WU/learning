#!/bin/bash
# 课 12 实验 31：定位干净实例也查不到的原因 —— 时间戳格式 / export 验证
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
CLEAN=http://localhost:8458

echo "===== [1] 用 export 端点看数据到底在不在（绕过查询层） ====="
curl -s --data-urlencode 'match[]=l12_clean_probe' "$CLEAN/api/v1/export" | head -c 400; echo
echo "-- 对照：查全库有没有任何 l12_ 开头的 --"
curl -s --data-urlencode 'match[]={__name__=~"l12_.*"}' "$CLEAN/api/v1/export" | head -c 400; echo

echo ""
echo "===== [2] 尝试不同时间戳格式 ====="
echo "-- 格式 A：无时间戳（VM 用当前时间） --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST --data-binary 'l12_ts_a{job="l12"} 1' "$CLEAN/api/v1/import/prometheus"
echo "-- 格式 B：秒级时间戳 --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST --data-binary "l12_ts_b{job=\"l12\"} 1 $(date +%s)" "$CLEAN/api/v1/import/prometheus"
echo "-- 格式 C：毫秒级时间戳 --"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" -X POST --data-binary "l12_ts_c{job=\"l12\"} 1 $(date +%s)000" "$CLEAN/api/v1/import/prometheus"
sleep 3
echo "-- 逐个查 --"
for n in l12_ts_a l12_ts_b l12_ts_c; do
  echo -n "  $n: "
  curl -s --data-urlencode "query=$n" "$CLEAN/api/v1/query" | head -c 150; echo
done

echo ""
echo "===== [3] 检查该实例的 vm_rows_ignored_total ====="
curl -s "$CLEAN/api/v1/query?query=sum%20by%20(reason)%20(vm_rows_ignored_total)" | head -c 400; echo
echo "-- vm_rows_inserted_total --"
curl -s "$CLEAN/api/v1/query?query=sum%20by%20(type)%20(vm_rows_inserted_total)" | head -c 400; echo

echo ""
echo "===== [4] 关键：search.maxStalenessInterval / lookback 设置 ====="
docker exec vm-clean-test sh -c '/victoria-metrics-prod --help 2>&1 | grep -A4 "search.maxStalenessInterval" | head -8'

echo ""
echo "===== [5] 用 query_range 明确时间窗查询 ====="
NOW=$(date +%s)
echo "-- 过去 10 分钟 --"
curl -s --data-urlencode 'query=l12_ts_a' --data-urlencode "start=$((NOW-600))" --data-urlencode "end=$NOW" --data-urlencode 'step=30' "$CLEAN/api/v1/query_range" | head -c 250; echo
echo "-- 过去 1 小时 --"
curl -s --data-urlencode 'query=l12_ts_a' --data-urlencode "start=$((NOW-3600))" --data-urlencode "end=$NOW" --data-urlencode 'step=60' "$CLEAN/api/v1/query_range" | head -c 250; echo

echo ""
echo "===== [6] 决定性：/api/v1/series 看序列是否注册 ====="
curl -s --data-urlencode 'match[]={__name__=~"l12_.*"}' "$CLEAN/api/v1/series" | head -c 400; echo
