#!/bin/bash
# 课 12 实验 21：选型决策 —— VM 的真实边界（不擅长的场景实测）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
VM=http://localhost:8428
PROM=http://localhost:9090

echo "===== [1] 边界 1：高基数（high cardinality）实测 ====="
echo "-- VM 侧：往 tenant 0 写入 20000 条高基数序列 --"
: > /tmp/l12_hc.txt
for i in $(seq 1 20000); do
  printf 'l12_highcard{job="l12",uid="%s"} %s %s000\n' "$i" "$((RANDOM % 1000))" "$(date +%s)" >> /tmp/l12_hc.txt
done
echo "  数据文件行数 = $(wc -l < /tmp/l12_hc.txt)"
S=$(date +%s%N)
curl -s -o /dev/null -w "  VM 写入 HTTP=%{http_code}\n" -X POST --data-binary @/tmp/l12_hc.txt "$VM/api/v1/import/prometheus"
E=$(date +%s%N)
echo "  写入耗时 = $(( (E-S)/1000000 )) ms"
sleep 3
echo "-- 高基数查询耗时 --"
curl -s -o /dev/null -w "  count(l12_highcard) 耗时=%{time_total}s\n" --data-urlencode 'query=count(l12_highcard)' "$VM/api/v1/query"
curl -s -o /dev/null -w "  sum(l12_highcard)   耗时=%{time_total}s\n" --data-urlencode 'query=sum(l12_highcard)' "$VM/api/v1/query"
curl -s -o /dev/null -w "  topk(10, l12_highcard) 耗时=%{time_total}s\n" --data-urlencode 'query=topk(10, l12_highcard)' "$VM/api/v1/query"

echo ""
echo "===== [2] 边界 2：数据删除与修改（VM 的弱项） ====="
echo "-- Prometheus 有 /api/v1/admin/tsdb/delete_series，VM 呢？ --"
curl -s -o /dev/null -w "  Prometheus delete_series HTTP=%{http_code}（需 --web.enable-admin-api）\n" \
  -X POST "$PROM/api/v1/admin/tsdb/delete_series?match[]=l12_highcard"
echo "-- VM 的删除 API --"
curl -s -o /dev/null -w "  VM /api/v1/admin/tsdb/delete_series HTTP=%{http_code}\n" \
  -X POST "$VM/api/v1/admin/tsdb/delete_series?match[]=l12_highcard"
echo "-- VM 实际的删除端点（企业版功能，社区版？） --"
curl -s -o /dev/null -w "  VM /admin/tsdb/delete_series HTTP=%{http_code}\n" \
  -X POST "$VM/admin/tsdb/delete_series?match[]=l12_highcard"
echo "-- 尝试删除后数据是否还在 --"
sleep 2
curl -s --data-urlencode 'query=count(l12_highcard)' "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  l12_highcard 剩余序列 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "===== [3] 边界 3：保留期与降采样（retention / downsampling） ====="
echo "-- VM 单节点的 -retentionPeriod 当前值 --"
curl -s "$VM/api/v1/status/flags" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
for k in ['retentionPeriod','dedup.minScrapeInterval','maxLabelsPerTimeseries','search.maxSeries']:
    print('   ', k, '=', d.get(k))
" 2>&1 | head -6
echo "-- Prometheus 对照 --"
curl -s "$PROM/api/v1/status/flags" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
print('   storage.tsdb.retention.time =', d.get('storage.tsdb.retention.time'))
" 2>&1 | head -3

echo ""
echo "===== [4] 边界 4：单条序列的写入频率上限（VM 对重复时间戳的处理） ====="
echo "-- 同一时间戳写不同值，VM 保留哪个？ --"
TS=$(date +%s)
curl -s -o /dev/null -X POST --data-binary "l12_dup{job=\"l12\"} 111 ${TS}000" "$VM/api/v1/import/prometheus"
curl -s -o /dev/null -X POST --data-binary "l12_dup{job=\"l12\"} 222 ${TS}000" "$VM/api/v1/import/prometheus"
sleep 2
curl -s --data-urlencode "query=l12_dup{job=\"l12\"}" "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  VM 同时间戳写入 111 再 222 -> 结果 =', r[0]['value'][1] if r else 'NONE')"

echo ""
echo "-- 对照：Prometheus 对同时间戳的处理 --"
curl -s -o /dev/null -X POST --data-binary "l12_dup{job=\"l12\"} 111 ${TS}000" "$PROM/api/v1/write" 2>/dev/null
echo "  （Prometheus remote write 需 snappy 压缩，此处跳过直接写入）"

echo ""
echo "===== [5] 边界 5：VM 是否支持事务 / 更新 / 删除单条数据 ====="
echo "-- MetricsQL 有没有 delete/update 类函数？ --"
curl -s "$VM/api/v1/query?query=nonexistent_func_for_delete_test(x)" 2>&1 | head -c 200; echo
echo "-- 确认：VM 是 append-only 时序库，不支持更新已写入的样本 --"

echo ""
echo "===== [6] 边界 6：labels 数量限制 ====="
echo "-- 构造 50 个 label 的序列写入 --"
LABELS=""
for i in $(seq 1 50); do LABELS="$LABELS,l$i=\"v$i\""; done
PAYLOAD="l12_manylabels{job=\"l12\"$LABELS} 1 $(date +%s)000"
curl -s -o /dev/null -w "  50 labels 写入 HTTP=%{http_code}\n" -X POST --data-binary "$PAYLOAD" "$VM/api/v1/import/prometheus"
sleep 2
curl -s --data-urlencode "query=l12_manylabels" "$VM/api/v1/query" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print('  查询到序列数 =', len(r))" 2>&1 | head -2
