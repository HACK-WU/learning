#!/bin/bash
# 课 7 核心实验 1：date_range 搜索 vs global 搜索
# 假设：带窄时间范围的查询走「按日期过滤」的快路径；
#       不带时间范围或范围极宽的查询退化成「全局扫描」慢路径。
Q() { curl -s --max-time 30 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
QR() { curl -s --max-time 60 --data-urlencode "query=$1" --data-urlencode "start=$2" --data-urlencode "end=$3" --data-urlencode "step=$4" http://localhost:8428/api/v1/query_range; }

g() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)["data"]["result"]
  print(int(float(d[0]["value"][1])) if d else 0)
except: print(-1)'; }

echo "=============================================="
echo " G1 基线：两种搜索的累计调用次数"
echo "=============================================="
DR0=$(g 'sum(vm_date_range_search_calls_total)')
GS0=$(g 'sum(vm_global_search_calls_total)')
echo "  date_range 搜索: $DR0"
echo "  global     搜索: $GS0"

echo
echo "=============================================="
echo " G2 实验 A：窄时间范围查询（1 小时）"
echo "=============================================="
NOW=$(date +%s); S=$((NOW-3600))
QR 'l06r_slow_value' "$S" "$NOW" 60 > /tmp/qa.json 2>&1
DR1=$(g 'sum(vm_date_range_search_calls_total)'); GS1=$(g 'sum(vm_global_search_calls_total)')
echo "  date_range 增量: $((DR1-DR0))"
echo "  global     增量: $((GS1-GS0))"

echo
echo "=============================================="
echo " G3 实验 B：无时间范围的瞬时查询"
echo "=============================================="
DR0=$DR1; GS0=$GS1
Q 'l06r_slow_value' > /tmp/qb.json 2>&1
DR1=$(g 'sum(vm_date_range_search_calls_total)'); GS1=$(g 'sum(vm_global_search_calls_total)')
echo "  date_range 增量: $((DR1-DR0))"
echo "  global     增量: $((GS1-GS0))"

echo
echo "=============================================="
echo " G4 实验 C：极宽时间范围（1 年）"
echo "=============================================="
DR0=$DR1; GS0=$GS1
NOW=$(date +%s); S=$((NOW-31536000))
QR 'l06r_slow_value' "$S" "$NOW" 3600 > /tmp/qc.json 2>&1
DR1=$(g 'sum(vm_date_range_search_calls_total)'); GS1=$(g 'sum(vm_global_search_calls_total)')
echo "  date_range 增量: $((DR1-DR0))"
echo "  global     增量: $((GS1-GS0))"

echo
echo "=============================================="
echo " G5 实验 D：正则匹配（最费的场景）"
echo "=============================================="
DR0=$DR1; GS0=$GS1
Q 'count({__name__=~"l06r_.*"})' > /tmp/qd.json 2>&1
DR1=$(g 'sum(vm_date_range_search_calls_total)'); GS1=$(g 'sum(vm_global_search_calls_total)')
echo "  date_range 增量: $((DR1-DR0))"
echo "  global     增量: $((GS1-GS0))"
echo "  正则缓存命中率:"
Q '1 - (sum(vm_cache_misses_total{type=~"storage/regexps|storage/regexpPrefixes|promql/regexp"}) / sum(vm_cache_requests_total{type=~"storage/regexps|storage/regexpPrefixes|promql/regexp"}))' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    %.1f%%" % (float(r["value"][1])*100))' 2>/dev/null

echo
echo "=============================================="
echo " G6 冷查询 vs 热查询：缓存到底省了多少"
echo "=============================================="
echo "  用同一条重查询，连续跑 3 次，看耗时变化"
QRY='sum(rate(vm_rows_inserted_total[5m])) by (type)'
for i in 1 2 3; do
  T=$(curl -s --max-time 60 --data-urlencode "query=$QRY" http://localhost:8428/api/v1/query \
      -o /dev/null -w '%{time_total}' 2>&1)
  echo "    第 $i 次: ${T}s"
done

echo
echo "=============================================="
echo " G7 tagFiltersLoops 缓存：118 条目占了 7.4MB"
echo "=============================================="
echo "  这是个异常情况，值得关注："
Q 'vm_cache_entries{type="indexdb/tagFiltersLoops"}' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    条目数: %d" % int(float(r["value"][1])))' 2>/dev/null
Q 'sum(vm_cache_size_bytes{type="indexdb/tagFiltersLoops"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    占用: %.0f 字节" % float(r["value"][1]))' 2>/dev/null
echo "  → 平均每条目: $(echo "scale=0;7471104/118"|bc) 字节"
echo "  对比 tsid: $(echo "scale=0;67108864/27682"|bc) 字节/条目"
