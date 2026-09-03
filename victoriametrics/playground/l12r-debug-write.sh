#!/bin/bash
echo "=== [1] 时间基准对比 ==="
echo "WSL  epoch : $(date +%s)  ($(date '+%Y-%m-%d %H:%M:%S %Z'))"
echo "容器 epoch : $(docker exec vmselect-learn date +%s 2>/dev/null)  ($(docker exec vmselect-learn date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null))"
echo "vm-storage : $(docker exec vmstorage-learn date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"

echo ""
echo "=== [2] 直接用 export 端点查 l12r_xmig_alpha（绕过查询延迟） ==="
NOW=$(date +%s)
START=$((NOW - 7200))
echo "export 窗口: ${START} -> ${NOW}"
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_.*"}' \
  --data-urlencode "start=${START}" --data-urlencode "end=${NOW}" | head -c 400
echo ""
echo "--- 不限制时间范围的 export ---"
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__=~"l12r_.*"}' | head -c 400
echo ""

echo ""
echo "=== [3] 用 export 查一个肯定存在的指标作对照 ==="
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__="up"}' | head -c 200
echo ""

echo ""
echo "=== [4] 立刻重新写入 1 条并马上 export 验证 ==="
TS=$(( $(date +%s) * 1000 ))
echo "写入时间戳(ms): ${TS}"
echo "{\"metric\":{\"__name__\":\"l12r_now_test\",\"idx\":\"0\"},\"values\":[999],\"timestamps\":[${TS}]}" \
  | curl -s -X POST --data-binary @- "http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus" -w " -> HTTP %{http_code}\n"
sleep 2
curl -s -G "http://localhost:8481/select/0/prometheus/api/v1/export" \
  --data-urlencode 'match[]={__name__="l12r_now_test"}' | head -c 300
echo ""

echo ""
echo "=== [5] 检查 vmstorage 是否有写入计数 ==="
curl -s "http://localhost:8482/metrics" 2>/dev/null | grep -E "vm_vminsert_metrics_read_total|vm_rows_inserted_total|vm_new_timeseries_created_total" | head -10
echo "--- vminsert 侧 ---"
curl -s "http://localhost:8480/metrics" 2>/dev/null | grep -E "vminsert_rows_inserted_total|vm_http_requests_total.*import" | head -10

echo ""
echo "=== [6] vmstorage 日志尾部（看有无写入/报错） ==="
docker logs vmstorage-learn --tail 15 2>&1 | tail -15
