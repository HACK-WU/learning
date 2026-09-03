#!/bin/bash
# 课 8：查不到的真相 —— 是 [10m] 窗口的语义问题
# 线索：range query 能查到 100 条，count_over_time[10m] 查不到
# 假设：count_over_time 的 [10m] 是相对「查询执行时刻」的窗口，
#       而我的数据是过去时间，落在窗口之外

echo "=============================================="
echo " C1 时间基准核对"
echo "=============================================="
NOW=$(date +%s)
echo "  当前时间: $NOW ($(date))"
echo "  l08_cluster 数据时间: 过去 600 秒起，10 个时间点，间隔 5 秒"
echo "  即: $((NOW-600)) ~ $((NOW-555))"
echo "  [10m] 窗口覆盖: $((NOW-600)) ~ $NOW"
echo "  → 数据应该在窗口内！"

echo
echo "=============================================="
echo " C2 直接对比几种查法"
echo "=============================================="
echo "  -- 1) count_over_time(l08_cluster_value[10m]) --"
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_cluster_value[10m])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     ", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "  -- 2) count_over_time(l08_cluster_value[2h]) --"
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_cluster_value[2h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     ", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "  -- 3) l08_cluster_value 瞬时（当前时刻）--"
curl -s --max-time 30 --data-urlencode 'query=l08_cluster_value' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     序列数:", len(r))' 2>&1

echo
echo "=============================================="
echo " C3 决定性：看数据实际落在哪个时间点"
echo "=============================================="
NOW=$(date +%s); S=$((NOW-7200))
curl -s --max-time 60 --data-urlencode 'query=l08_cluster_value{idx="0"}' \
  --data-urlencode "start=$S" --data-urlencode "end=$NOW" --data-urlencode "step=60" \
  'http://localhost:8481/select/0/prometheus/api/v1/query_range' \
  | python3 -c '
import json,sys,datetime
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
for x in r:
    print("   idx=0 的点:")
    for v in x["values"]:
        ts=int(v[0])
        print("      ", datetime.datetime.fromtimestamp(ts).strftime("%H:%M:%S"), "=", v[1])
' 2>&1

echo
echo "=============================================="
echo " C4 重新生成数据：这次让数据落在「最近 10 分钟」内"
echo "=============================================="
M="l08_c4_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
mark = sys.argv[1]
now = int(time.time())
# 过去 5 分钟内的 10 个点，间隔 30 秒
lines = []
for i in range(10):
    ts = (now - 300 + i*30) * 1000000000
    lines.append("%s,idx=%d value=%d %d" % (mark, i % 3, i, ts))
open("/tmp/l08_c4.influx","w").write("\n".join(lines)+"\n")
print("  生成 %s: 过去 5 分钟，10 个点" % mark)
PY
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_c4.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'
sleep 3

echo "  -- count_over_time[10m] --"
curl -s --max-time 30 --data-urlencode "query=count_over_time(${M}_value[10m])" \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     ", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "  -- count() 瞬时（默认 5 分钟 lookbehind）--"
curl -s --max-time 30 --data-urlencode "query=count(${M}_value)" \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     ", int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo
echo "=============================================="
echo " C5 结论"
echo "=============================================="
echo "  C4 的数据落在最近 5 分钟内，两种查法都应该能查到。"
echo "  如果 C4 能查到而 D6 查不到 → 证明是【时间窗口】问题："
echo "    count_over_time[m] 与 count() 的 lookbehind 都是相对"
echo "    【查询执行时刻】的窗口，数据必须在窗口内才可见。"
