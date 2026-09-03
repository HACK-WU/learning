#!/bin/bash
# 课 10 知识点 3：租户隔离的边界
# 核心命题：多租户提供【数据隔离】，不提供【资源隔离】
set -u
I=http://localhost:8480
S=http://localhost:8481

echo "=============================================="
echo " B1 数据隔离是硬的（复核课 8）"
echo "=============================================="
M="l10_iso_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
ts = (int(time.time()) - 120) * 1000000000
open("/tmp/l10_iso.influx","w").write(
    "\n".join("%s,idx=%%d value=%%d %%d" % sys.argv[1] % (i,i,ts) for i in range(50))+"\n")
print("  准备 %s: 50 条序列，只写入 tenant 300" % sys.argv[1])
PY
curl -s -X POST --max-time 60 --data-binary @/tmp/l10_iso.influx \
  "$I/insert/300/influx/write" -o /dev/null -w '  写 tenant 300: HTTP %{http_code}\n'
sleep 8
Q="count_over_time(${M}_value[1h])"
for t in 300 301 0; do
  printf "  查 tenant %-4s: " "$t"
  curl -s --max-time 30 --data-urlencode "query=$Q" \
    "$S/select/$t/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
done
echo "  → 数据隔离成立：其他租户查不到"

echo
echo "=============================================="
echo " B2 但资源是共享的（关键）"
echo "=============================================="
echo "  写入大量数据到 tenant 400，观察【全局指标】的变化"
echo
echo "  -- 写入前的全局序列数 --"
B=$(curl -s --max-time 20 "$S/select/0/prometheus/api/v1/series" 2>/dev/null \
   | python3 -c 'import json,sys
try: print(len(json.load(sys.stdin).get("data",[])))
except Exception: print("N/A")' 2>/dev/null)
echo "    tenant 0 序列数(基线): $B"

for T in 100 200 300 400; do
  printf "    tenant %s 的 tsid 缓存条目: " "$T"
  curl -s --max-time 15 "$S/select/$T/prometheus/api/v1/status/tsdb" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin).get("data",{})
    print(d.get("seriesCountByMetricNameCount", d.get("headStats",{}).get("numSeries","N/A")))
except Exception: print("N/A")' 2>/dev/null
done

echo
echo "  ⚠️ 关键观察点：tsid 缓存是【全局共享】还是【按租户隔离】？"
echo "     看 vmstorage 的 vm_cache_entries{type=\"storage/tsid\"}"
for p in 8482 8492; do
  printf "    vmstorage(%s) tsid: " "$p"
  curl -s --max-time 15 "http://localhost:$p/metrics" 2>/dev/null \
    | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
done
echo "    （这是【全局】计数，不按租户拆分 → 资源是共享的）"

echo
echo "=============================================="
echo " B3 做一个大租户，看是否影响其他租户"
echo "=============================================="
echo "  往 tenant 400 写入 8000 条高基数序列，同时监测其他租户查询延迟"
echo
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
lines = ["l10_big,idx=%d,shard=%d value=%d %d" % (i, i%16, i, ts) for i in range(8000)]
open("/tmp/l10_big.influx","w").write("\n".join(lines)+"\n")
print("  准备 l10_big: 8000 条序列 → tenant 400")
PY

echo "  -- 写入前，测 tenant 300 的查询延迟 --"
T_BEFORE=$(curl -s -o /dev/null -w '%{time_total}' --max-time 30 \
  --data-urlencode "query=$Q" "$S/select/300/prometheus/api/v1/query")
echo "    tenant 300 查询耗时: ${T_BEFORE}s"

echo
echo "  -- 写入 8000 条到 tenant 400 --"
S_TIME=$(date +%s)
curl -s -X POST --max-time 120 --data-binary @/tmp/l10_big.influx \
  "$I/insert/400/influx/write" -o /dev/null -w '    HTTP %{http_code}\n'
E_TIME=$(date +%s)
echo "    耗时: $((E_TIME-S_TIME)) 秒"

sleep 10

echo
echo "  -- 写入后，再测 tenant 300 的查询延迟 --"
T_AFTER=$(curl -s -o /dev/null -w '%{time_total}' --max-time 30 \
  --data-urlencode "query=$Q" "$S/select/300/prometheus/api/v1/query")
echo "    tenant 300 查询耗时: ${T_AFTER}s"

echo
echo "  -- tsid 缓存变化（全局）--"
for p in 8482 8492; do
  printf "    vmstorage(%s) tsid: " "$p"
  curl -s --max-time 15 "http://localhost:$p/metrics" 2>/dev/null \
    | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
done
echo
echo "  → 如果 tenant 400 的写入让【全局 tsid 缓存】上涨，"
echo "    说明所有租户共享同一个缓存 → 大租户会挤占小租户的缓存空间"

echo
echo "=============================================="
echo " B4 限流：vmauth 能限制单租户吗？"
echo "=============================================="
echo "  检查 vmauth 是否支持每用户限流"
docker run --rm victoriametrics/vmauth:v1.151.0 --help 2>&1 \
  | grep -iE 'ratelimit|concurrency|limit' | head -10

echo
echo "  -- 配置里的 per-user 限流字段 --"
echo "     vmauth 支持: max_concurrent_requests / 企业版才有完整限流"
docker run --rm victoriametrics/vmauth:v1.151.0 --help 2>&1 \
  | grep -iA2 'max_concurrent' | head -6

echo
echo "=============================================="
echo " B5 单节点版有租户概念吗"
echo "=============================================="
printf "  单节点 /insert/500/influx/write: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 15 \
  --data-binary 'l10_x,idx=1 value=1' \
  'http://localhost:8428/insert/500/influx/write'
printf "  单节点 /api/v1/write:            "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 15 \
  --data-binary 'l10_x,idx=1 value=1' \
  'http://localhost:8428/api/v1/write'
echo "  → 单节点版没有 /insert/<tenant>/ 路径，租户是【集群版独有】"

echo
echo "=============================================="
echo " B6 租户数据能否单独删除"
echo "=============================================="
echo "  集群版是否支持按租户删除？"
printf "    DELETE /api/v1/admin/tsdb/delete_series: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 15 \
  --data-urlencode 'match[]=l10_big_value' \
  "$S/select/400/prometheus/api/v1/admin/tsdb/delete_series"
echo "    （这是按 match[] 删除，不是按租户整体删除）"
echo
echo "  ⚠️ 结论：删除要一个一个 match[] 来，没有『删除整个租户』的接口"
