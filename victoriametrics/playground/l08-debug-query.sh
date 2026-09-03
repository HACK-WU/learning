#!/bin/bash
# 课 8 排查：写入 204 但查不到
# 假设：count() 是瞬时查询，只看「当前时刻」；数据是过去时间，所以查不到
#       这正是课 6 踩过的坑

Q() { curl -s --max-time 30 --data-urlencode "query=$1" \
        'http://localhost:8481/select/0/prometheus/api/v1/query'; }
QR() { curl -s --max-time 60 --data-urlencode "query=$1" \
        --data-urlencode "start=$2" --data-urlencode "end=$3" --data-urlencode "step=$4" \
        'http://localhost:8481/select/0/prometheus/api/v1/query_range'; }

echo "=============================================="
echo " T1 瞬时查询 vs 范围查询"
echo "=============================================="
echo "-- count(l08_cluster_value) 瞬时 --"
Q 'count(l08_cluster_value)' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   结果:", int(float(r[0]["value"][1])) if r else "空 → 当前时刻没有样本")' 2>&1

echo "-- count_over_time(l08_cluster_value[2h]) --"
Q 'count_over_time(l08_cluster_value[2h])' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   样本数:", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "-- 直接查原始值 --"
Q 'l08_cluster_value' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   序列数:", len(r))
for x in r[:3]: print("     ", x["metric"], "=", x["value"][1])' 2>&1

echo
echo "=============================================="
echo " T2 用 range query 查过去的数据"
echo "=============================================="
NOW=$(date +%s); S=$((NOW-3600))
QR 'count(l08_cluster_value)' "$S" "$NOW" 300 \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
if not r: print("   空"); raise SystemExit
vals=r[0]["values"]
print("   时间点数:", len(vals))
nz=[v for v in vals if float(v[1])>0]
print("   非零时间点:", len(nz))
if nz: print("   最新非零值:", nz[-1])' 2>&1

echo
echo "=============================================="
echo " T3 对照：单节点上同一份数据"
echo "=============================================="
echo "-- 单节点 count() 瞬时 --"
curl -s --max-time 30 --data-urlencode 'query=count(l08_cluster_value)' \
  'http://localhost:8428/api/v1/query' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   结果:", int(float(r[0]["value"][1])) if r else "空")' 2>&1
echo "-- 单节点 count_over_time --"
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_cluster_value[2h])' \
  'http://localhost:8428/api/v1/query' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("   样本数:", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo
echo "=============================================="
echo " T4 写入当前时刻的数据，验证瞬时查询"
echo "=============================================="
python3 - <<'PY'
import subprocess
now = int(subprocess.check_output(["date", "+%s"]).decode().strip())
lines = []
for i in range(10):
    lines.append('l08_now,idx=%d value=%d.0 %d' % (i, i, now * 1000000000))
open("/tmp/l08_now.influx", "w").write("\n".join(lines) + "\n")
print("  生成 10 条当前时刻的数据")
PY
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_now.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  HTTP: %{http_code}\n'
sleep 3
echo "  -- 现在 count() 瞬时 --"
Q 'count(l08_now_value)' | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("    结果:", int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo
echo "=============================================="
echo " T5 结论"
echo "=============================================="
echo "  写入 204 = 成功。查不到是因为 count() 只看当前时刻，"
echo "  而实验数据写的是过去时间 —— 这是课 6 踩过的同一个坑。"
echo "  验证过去数据要用 count_over_time() 或 range query。"
