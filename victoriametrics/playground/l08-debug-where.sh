#!/bin/bash
# 课 8：数据写进去了(220 新序列)但查不到 —— 到底在哪？
# 关键线索：vm_new_timeseries_created_total = 220，说明 vmstorage 收到了

echo "=============================================="
echo " V1 直接问 vmstorage 它有多少序列"
echo "=============================================="
curl -s --max-time 20 'http://localhost:8482/metrics' 2>/dev/null \
  | grep -E '^vm_(cache_entries\{type="storage/tsid"|new_timeseries_created_total|rows_inserted_total)' | head -5

echo
echo "  -- tsid 缓存条目数（= 已注册的序列数）--"
curl -s --max-time 20 'http://localhost:8482/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -2

echo
echo "=============================================="
echo " V2 列出所有 l08_ 开头的序列（用 series API）"
echo "=============================================="
curl -s --max-time 30 --data-urlencode 'match[]={__name__=~"l08_.*"}' \
  'http://localhost:8481/select/0/prometheus/api/v1/series' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
if "data" not in d: print("   错误:", d); raise SystemExit
names=set()
for x in d["data"]: names.add(x.get("__name__","?"))
print("   匹配序列数:", len(d["data"]))
for n in sorted(names): print("     ", n)' 2>&1

echo
echo "=============================================="
echo " V3 用 /api/v1/label/__name__/values 看有哪些指标"
echo "=============================================="
curl -s --max-time 30 'http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
v=d.get("data",[])
l8=[x for x in v if x.startswith("l08")]
print("   总指标数:", len(v))
print("   l08_ 开头的指标:")
for x in sorted(l8): print("     ", x)' 2>&1

echo
echo "=============================================="
echo " V4 关键：查一个很宽的时间范围"
echo "=============================================="
NOW=$(date +%s); S=$((NOW-7200))
echo "  -- l08_cluster_value 在最近 2 小时 --"
curl -s --max-time 60 --data-urlencode 'query=l08_cluster_value' \
  --data-urlencode "start=$S" --data-urlencode "end=$NOW" --data-urlencode "step=600" \
  'http://localhost:8481/select/0/prometheus/api/v1/query_range' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   序列数:", len(r))
if r:
  tot=sum(len(x["values"]) for x in r)
  print("   总点数:", tot)' 2>&1

echo
echo "=============================================="
echo " V5 对照实验：往【单节点】写同样的数据，看能不能立刻查到"
echo "=============================================="
M="l08_v5_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 60) * 1000000000
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(3)]
open("/tmp/l08_v5.influx","w").write("\n".join(lines)+"\n")
PY
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_v5.influx \
  'http://localhost:8428/write' -o /dev/null -w '  单节点写入 HTTP %{http_code}\n'
sleep 2
echo -n "  单节点 count_over_time[10m]: "
curl -s --max-time 30 --data-urlencode "query=count_over_time(${M}_value[10m])" \
  'http://localhost:8428/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo -n "  单节点 count() 瞬时: "
curl -s --max-time 30 --data-urlencode "query=count(${M}_value)" \
  'http://localhost:8428/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo
echo "=============================================="
echo " V6 结论推导"
echo "=============================================="
echo "  如果 V5 单节点也查不到 → 是通用时序问题，不是集群特性"
echo "  如果 V5 单节点能查到 → 是集群特有的缓冲延迟"
