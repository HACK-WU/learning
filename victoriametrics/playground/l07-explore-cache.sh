#!/bin/bash
# 课 7 探索：缓存分层、命中率、内存占用
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
FMT='import json,sys
d=json.load(sys.stdin)["data"]["result"]
if not d: print("  (无数据)")
for r in d:
    m=r["metric"]; lbl=" ".join("%s=%s"%(k,v) for k,v in sorted(m.items()) if k!="__name__")
    try: val=float(r["value"][1])
    except: val=0
    if val==0: continue
    print("  %-46s %14.0f" % (lbl or "-", val))
'

echo "=============================================="
echo " C1 vm_cache_entries 按 type 拆分（缓存里装了什么）"
echo "=============================================="
Q 'sum(vm_cache_entries) by (type)' | python3 -c "$FMT"

echo
echo "=============================================="
echo " C2 vm_cache_size_bytes（各缓存占多大内存）"
echo "=============================================="
Q 'sum(vm_cache_size_bytes) by (type)' | python3 -c "$FMT"

echo
echo "=============================================="
echo " C3 vm_cache_size_max_bytes（各自的上限）"
echo "=============================================="
Q 'sum(vm_cache_size_max_bytes) by (type)' | python3 -c "$FMT"

echo
echo "=============================================="
echo " C4 命中率：requests vs misses"
echo "=============================================="
echo "-- requests --"
Q 'sum(vm_cache_requests_total) by (type)' | python3 -c "$FMT"
echo "-- misses --"
Q 'sum(vm_cache_misses_total) by (type)' | python3 -c "$FMT"

echo
echo "-- 计算命中率 --"
Q '1 - (sum(vm_cache_misses_total) by (type) / sum(vm_cache_requests_total) by (type))' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d:
    t=r["metric"].get("type","-")
    try: v=float(r["value"][1])
    except: continue
    print("  %-46s %10.2f%%" % (t, v*100))' 2>&1

echo
echo "=============================================="
echo " C5 缓存的其他行为指标"
echo "=============================================="
for m in vm_cache_collisions_total vm_cache_rotations_total vm_cache_resets_total vm_cache_syncs_total; do
  echo "-- $m --"
  Q "sum($m) by (type)" | python3 -c "$FMT"
done

echo
echo "=============================================="
echo " C6 查询侧缓存：rollup result cache"
echo "=============================================="
for m in vm_rollup_result_cache_requests_total vm_rollup_result_cache_full_hits_total vm_rollup_result_cache_partial_hits_total vm_rollup_result_cache_miss_total; do
  R=$(Q "sum($m)" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("%.0f" % float(d[0]["value"][1]) if d else "无")' 2>/dev/null)
  echo "  $m : $R"
done

echo
echo "=============================================="
echo " C7 搜索优化计数器（课 7 性能核心）"
echo "=============================================="
for m in vm_date_range_search_calls_total vm_global_search_calls_total vm_search_max_unique_timeseries vm_memory_intensive_queries_total; do
  echo "-- $m --"
  Q "$m" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
if not d: print("   (无)")
for r in d: print("   %s" % r["value"][1])' 2>&1 | head -3
done

echo
echo "=============================================="
echo " C8 每次查询扫描多少数据"
echo "=============================================="
echo "-- vm_rows_scanned_per_query --"
Q 'sum(vm_rows_scanned_per_query_sum)/sum(vm_rows_scanned_per_query_count)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("   平均每次查询扫描 %.0f 行" % float(r["value"][1]))' 2>/dev/null
echo "-- vm_rows_read_per_query --"
Q 'sum(vm_rows_read_per_query_sum)/sum(vm_rows_read_per_query_count)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("   平均每次查询读取 %.0f 行" % float(r["value"][1]))' 2>/dev/null
echo "-- vm_series_read_per_query --"
Q 'sum(vm_series_read_per_query_sum)/sum(vm_series_read_per_query_count)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("   平均每次查询读取 %.0f 条序列" % float(r["value"][1]))' 2>/dev/null
