#!/bin/bash
# 课 7 实验 2：隔离测量 —— 停掉自抓取干扰，测真实查询路径
# 思路：用 vm_search_max_unique_timeseries 之外的指标，
#       直接对比「同一查询，不同写法」的耗时与扫描行数
Q() { curl -s --max-time 30 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " H1 确认 date_range 计数器的增长来源"
echo "=============================================="
A=$(Q 'sum(vm_date_range_search_calls_total)' | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
echo "  T0: $A"
sleep 20
B=$(Q 'sum(vm_date_range_search_calls_total)' | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
echo "  T0+20s（什么都不做）: $B   增量 $((B-A))"
echo
echo "  → 若增量 > 0，说明自抓取（-selfScrapeInterval=10s）在持续产生搜索，"
echo "    计数器无法归因到我的单次查询。改用「耗时对比法」。"

echo
echo "=============================================="
echo " H2 对照实验：三种查询写法的耗时差异"
echo "=============================================="
echo "  每种跑 5 次取中位数，减少抖动"
bench() {
  local label="$1"; local q="$2"
  local times=""
  for i in 1 2 3 4 5; do
    t=$(curl -s --max-time 60 --data-urlencode "query=$q" http://localhost:8428/api/v1/query \
        -o /dev/null -w '%{time_total}' 2>&1)
    times="$times $t"
  done
  med=$(echo $times | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int(NR/2)+1]}')
  printf "  %-40s 中位 %s s   (全部:%s)\n" "$label" "$med" "$times"
}

bench "A 精确匹配单序列"    'l06r_slow_value{idx="0"}'
bench "B 精确匹配全序列"    'l06r_slow_value'
bench "C 正则前缀匹配"      '{__name__=~"l06r_.*"}'
bench "D 正则(带^锚定)"     '{__name__=~"^l06r_.*$"}'
bench "E 多值匹配"          'l06r_slow_value{idx=~"1|2|3"}'

echo
echo "=============================================="
echo " H3 时间范围宽度对耗时的影响"
echo "=============================================="
bench_range() {
  local label="$1"; local secs="$2"
  NOW=$(date +%s); S=$((NOW-secs))
  local times=""
  for i in 1 2 3; do
    t=$(curl -s --max-time 60 --data-urlencode "query=avg_over_time(l06r_slow_value[${secs}s])" \
        http://localhost:8428/api/v1/query -o /dev/null -w '%{time_total}' 2>&1)
    times="$times $t"
  done
  printf "  %-24s 中位 %s s\n" "$label [${secs}s]" "$(echo $times | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int(NR/2)+1]}')"
}
bench_range "窄窗口" 300
bench_range "中窗口" 3600
bench_range "宽窗口" 86400

echo
echo "=============================================="
echo " H4 rows_scanned vs rows_read：过滤掉了多少"
echo "=============================================="
echo "  这两个指标的差值 = VM 靠索引/块头跳过的数据量"
Q 'sum(vm_rows_scanned_per_query_sum)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    累计 scanned: %.0f 行" % float(d[0]["value"][1]))' 2>/dev/null
Q 'sum(vm_rows_read_per_query_sum)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    累计 read:    %.0f 行" % float(d[0]["value"][1]))' 2>/dev/null
Q 'sum(vm_rows_scanned_per_query_sum)/sum(vm_rows_read_per_query_sum)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
v=float(d[0]["value"][1])
print("    scanned/read = %.3f  (即 %.1f%% 被跳过了)" % (v,(1-1/v)*100))' 2>/dev/null

echo
echo "=============================================="
echo " H5 tagFiltersLoops 异常：单条目 63KB"
echo "=============================================="
echo "  83 条目占 10.35 MB，而 tsid 是 27682 条目占 64MB（2.4KB/条）"
echo "  tagFiltersLoops 缓存的是「标签过滤条件 → 匹配的 metricID 集合」"
echo "  单条目 63KB 说明某个查询展开出了极大的 metricID 列表"
echo
echo "  resets 次数（缓存被清空的次数）:"
Q 'sum(vm_cache_resets_total) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    %-34s %6.0f" % (r["metric"].get("type","-"), float(r["value"][1])))' 2>/dev/null
echo
echo "  → resets 高说明缓存频繁失效，这是需要关注的信号"
