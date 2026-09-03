#!/bin/bash
# 排查：写入 5000 条序列后 hour_metric_ids 计数没涨
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
g() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)["data"]["result"]
  print("%.0f" % float(d[0]["value"][1]) if d else 0)
except: print(0)'; }

echo "=============================================="
echo " N1 数据写进去了吗？"
echo "=============================================="
echo "-- l07_marginal_value 能查到吗 --"
Q 'count(l07_marginal_value)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    count():", int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null
Q 'count_over_time(l07_marginal_value[30m])' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    count_over_time[30m]:", int(sum(float(r["value"][1]) for r in d)))' 2>/dev/null
echo "-- influx 累计写入 --"
Q 'sum(vm_rows_inserted_total{type="influx"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    influx 累计:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null

echo
echo "=============================================="
echo " N2 hour_metric_ids 到底是什么"
echo "=============================================="
echo "-- 不 sum，看原始标签 --"
Q 'vm_cache_entries{type="storage/hour_metric_ids"}' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    条目数:", len(d))
for r in d[:5]:
    lbl=" ".join("%s=%s"%(k,v) for k,v in r["metric"].items() if k!="__name__" and k!="type")
    print("      %-40s %s" % (lbl, r["value"][1]))
' 2>/dev/null

echo
echo "=============================================="
echo " N3 用 tsdb status 看权威的序列总数"
echo "=============================================="
curl -s --max-time 20 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('    totalSeries:', d.get('totalSeries'))
" 2>&1

echo
echo "=============================================="
echo " N4 关键：hour_metric_ids 是【按小时分桶】的缓存"
echo "=============================================="
echo "  它缓存的是『某一小时内出现过的 metricID』，"
echo "  用于加速带时间范围的查询（date_range search）。"
echo "  新写入的数据落在【当前小时】，可能需要等缓存 sync 才计入。"
echo
echo "  vm_cache_syncs_total（同步次数）:"
Q 'sum(vm_cache_syncs_total) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    %-30s %6.0f" % (r["metric"].get("type","-"), float(r["value"][1])))' 2>/dev/null

echo
echo "=============================================="
echo " N5 改用更可靠的序列计数方式"
echo "=============================================="
echo "-- 查所有 l07_marginal 序列（用 series API）--"
curl -s --max-time 30 --data-urlencode 'match[]=l07_marginal_value' \
  'http://localhost:8428/api/v1/series' 2>&1 | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)["data"]
    print("    序列数:", len(d))
except Exception as e: print("    失败:", e)' 2>/dev/null

echo
echo "-- 再等 15 秒看 hour_metric_ids 是否追上 --"
sleep 15
g 'sum(vm_cache_entries{type="storage/hour_metric_ids"})' | awk '{print "    hour_metric_ids(15s后):", $1}'

echo
echo "=============================================="
echo " N6 备选方案：用 metricIDs 缓存条目数衡量"
echo "=============================================="
Q 'sum(vm_cache_entries{type="storage/metricIDs"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    storage/metricIDs 条目:", int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null
Q 'sum(vm_cache_entries{type="storage/tsid"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    storage/tsid 条目:", int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null
Q 'sum(vm_cache_entries{type="storage/metricName"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    storage/metricName 条目:", int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null
