#!/bin/bash
# 课 8：查不到新写入的数据 —— 是时序问题还是别的原因？
# 假设1：时间戳精度/时区问题
# 假设2：count() 的 lookbehind 窗口（默认 5 分钟）不够
# 假设3：metric name 生成有问题

echo "=============================================="
echo " D1 检查时间戳是否正常"
echo "=============================================="
python3 - <<'PY'
import subprocess, time
now = int(subprocess.check_output(["date", "+%s"]).decode().strip())
print("  date +%s  =", now)
print("  python now =", int(time.time()))
print("  差值 =", now - int(time.time()))
print("  date 可读 =", subprocess.check_output(["date"]).decode().strip())
print("  UTC      =", subprocess.check_output(["date","-u"]).decode().strip())
PY

echo
echo "=============================================="
echo " D2 看看刚写的数据文件"
echo "=============================================="
head -3 /tmp/l08_vis.influx 2>&1
echo "  ..."
head -3 /tmp/l08_flush.influx 2>&1

echo
echo "=============================================="
echo " D3 用绝对正确的时间戳重写，并立即查"
echo "=============================================="
M="l08_d3_$(date +%s)"
python3 - "$M" <<'PY'
import subprocess, sys, time
mark = sys.argv[1]
now = int(time.time())
print("  使用的纳秒时间戳:", now*1000000000)
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, now*1000000000) for i in range(3)]
open("/tmp/l08_d3.influx","w").write("\n".join(lines)+"\n")
PY
echo "  写入内容:"
cat /tmp/l08_d3.influx
echo
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_d3.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'

echo
echo "  -- 立刻用 range query 查（避开 count() 的 lookbehind）--"
NOW=$(date +%s); S=$((NOW-300)); E=$((NOW+300))
curl -s --max-time 30 --data-urlencode "query=${M}_value" \
  --data-urlencode "start=$S" --data-urlencode "end=$E" --data-urlencode "step=60" \
  'http://localhost:8481/select/0/prometheus/api/v1/query_range' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   序列数:", len(r))
for x in r: print("     ", x["metric"].get("idx"), "->", x["values"][-1] if x["values"] else "空")' 2>&1

echo
echo "=============================================="
echo " D4 用 count_over_time 查（不依赖 lookbehind）"
echo "=============================================="
curl -s --max-time 30 --data-urlencode "query=count_over_time(${M}_value[10m])" \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   count_over_time:", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo
echo "=============================================="
echo " D5 对照：已经能查到的 l08_cluster_value 是怎么写的"
echo "=============================================="
echo "  l08_cluster 用的是「过去 600 秒起」的时间戳，已经能查到 38 条"
echo "  新写的用「当前时刻」时间戳，查不到"
echo
echo "  → 关键差别：是不是数据还在内存里没 flush？"
echo
echo "  -- 查 vmstorage 的缓存/未落盘指标 --"
curl -s --max-time 10 'http://localhost:8482/metrics' 2>/dev/null \
  | grep -E 'vm_active_merges|vm_new_timeseries_created_total|vm_rows_inserted_total' | head -6

echo
echo "=============================================="
echo " D6 决定性实验：写「过去 60 秒」的数据再查"
echo "=============================================="
M2="l08_d6_$(date +%s)"
python3 - "$M2" <<'PY'
import subprocess, sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 60) * 1000000000   # 过去 60 秒
print("  时间戳: 过去 60 秒")
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(3)]
open("/tmp/l08_d6.influx","w").write("\n".join(lines)+"\n")
PY
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_d6.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'
sleep 2
echo -n "  count_over_time[10m] 立即查: "
curl -s --max-time 30 --data-urlencode "query=count_over_time(${M2}_value[10m])" \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1
