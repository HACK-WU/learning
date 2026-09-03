#!/usr/bin/env bash
# 课 3 核心实测：MetricsQL 与 PromQL 的关键行为差异
set -u
BASE="http://localhost:8428"
NOW=$(date +%s); NOW=$(( NOW - NOW % 15 ))

q() {  # q "标签" "query" [extra_args...]
  local label="$1" query="$2"; shift 2
  echo "--- $label ---"
  echo "    query: $query"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode "query=$query" \
    --data-urlencode "time=$NOW" \
    "$@" \
  | python3 -c '
import sys,json
d=json.load(sys.stdin)
if d.get("status")!="success":
    print("    ERROR:", d.get("error","?")); sys.exit()
r=d["data"]["result"]
print(f"    命中 {len(r)} 条")
for it in r[:4]:
    m=it["metric"]; v=it["value"][1]
    name=m.get("__name__","(无名称)")
    labs={k:x for k,x in m.items() if k!="__name__"}
    print(f"      {name} {labs} = {v}")
'
}

echo "########## A. 保留指标名（MetricsQL vs PromQL 最大差异）##########"
q "A1 sum_over_time 后是否保留指标名" 'sum_over_time(l3_gappy[5m])'
q "A2 round 后是否保留指标名" 'round(l3_gappy)'

echo
echo "########## B. 省略 lookbehind 窗口 ##########"
q "B1 rate 带窗口 [5m]" 'rate(l3_counter_total[5m])'
q "B2 rate 省略窗口"    'rate(l3_counter_total)'
q "B3 increase 带窗口"  'increase(l3_counter_total[5m])'
q "B4 increase 省略窗口" 'increase(l3_counter_total)'

echo
echo "########## C. gap 填补：keep_last_value ##########"
GAP_T=$(( $(date +%s) - 3600 + 1500 ))   # gap 中间点
GAP_T=$(( GAP_T - GAP_T % 15 ))
echo "  (gap 时间点: $(date -d @${GAP_T} '+%H:%M:%S'))"
q "C1 原始值（gap 处应为空）" 'l3_gappy' --data-urlencode "time=$GAP_T"
q "C2 keep_last_value 填补"  'keep_last_value(l3_gappy)' --data-urlencode "time=$GAP_T"
q "C3 PromQL 等价写法（对比）" 'l3_gappy or last_over_time(l3_gappy[1h])' --data-urlencode "time=$GAP_T"

echo
echo "########## D. default / if / ifnot 操作符 ##########"
q "D1 default 填 0" 'l3_nonexistent_metric default 0'
q "D2 无 default（应为空）" 'l3_nonexistent_metric'

echo
echo "########## E. 多 or 过滤器 ##########"
q "E1 多 or 过滤器" '{job="api",instance="i1" or job="web",instance="i3"}'

echo
echo "########## F. topk / limit / median ##########"
q "F1 topk 3" 'topk(3, l3_mem_bytes)'
q "F2 sum by limit" 'sum(l3_mem_bytes) by (dc) limit 2'
q "F3 median" 'median(l3_mem_bytes)'

echo
echo "########## G. WITH 模板 ##########"
q "G1 WITH 模板" 'WITH (x = l3_mem_bytes) x / 1024'

echo
echo "########## H. 时间戳对齐（兼容性测试提到的差异）##########"
echo "  用非对齐时间戳查询，观察返回的时间戳"
for t in $((NOW+7)) $((NOW)); do
  echo "  -- 请求 time=$t --"
  curl -s -m 20 -G "$BASE/api/v1/query" \
    --data-urlencode 'query=l3_gappy' --data-urlencode "time=$t" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("     返回时间戳:", r[0]["value"][0] if r else "(空)")'
done
