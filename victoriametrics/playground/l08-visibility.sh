#!/bin/bash
# 课 8 关键实验：写入后多久能查到？
# 单节点 vs 集群 对照，并测 force_flush 的效果

Q1() { curl -s --max-time 30 --data-urlencode "query=$1" 'http://localhost:8428/api/v1/query'; }
QC() { curl -s --max-time 30 --data-urlencode "query=$1" 'http://localhost:8481/select/0/prometheus/api/v1/query'; }
n1() { Q1 "$1" | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else 0)' 2>/dev/null; }
nc() { QC "$1" | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else 0)' 2>/dev/null; }

echo "=============================================="
echo " F1 写入当前时刻数据，逐秒观测可见性"
echo "=============================================="
MARK="l08_vis_$(date +%s)"
python3 - "$MARK" <<'PY'
import subprocess, sys
mark = sys.argv[1]
now = int(subprocess.check_output(["date", "+%s"]).decode().strip())
lines = ["%s,idx=%d value=%d.0 %d" % (mark, i, i, now*1000000000) for i in range(5)]
open("/tmp/l08_vis.influx", "w").write("\n".join(lines)+"\n")
print("  标记: %s" % mark)
PY

echo "  -- 写入集群 --"
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_vis.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '    HTTP %{http_code}\n'
echo "  -- 写入单节点 --"
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_vis.influx \
  'http://localhost:8428/write' -o /dev/null -w '    HTTP %{http_code}\n'

echo
echo "  逐秒观测 count(${MARK}_value):"
printf "    %-6s %-10s %-10s\n" "秒" "集群" "单节点"
for s in 1 2 3 5 8 12; do
  sleep $([ $s -eq 1 ] && echo 1 || echo $((s-prev)))
  prev=$s
  printf "    %-6s %-10s %-10s\n" "$s" "$(nc "count(${MARK}_value)")" "$(n1 "count(${MARK}_value)")"
done

echo
echo "=============================================="
echo " F2 force_flush 能不能立刻可见？"
echo "=============================================="
MARK2="l08_flush_$(date +%s)"
python3 - "$MARK2" <<'PY'
import subprocess, sys
mark = sys.argv[1]
now = int(subprocess.check_output(["date", "+%s"]).decode().strip())
lines = ["%s,idx=%d value=%d.0 %d" % (mark, i, i, now*1000000000) for i in range(5)]
open("/tmp/l08_flush.influx", "w").write("\n".join(lines)+"\n")
print("  标记: %s" % mark)
PY

curl -s -X POST --max-time 30 --data-binary @/tmp/l08_flush.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null
echo -n "  写入后立刻查: "
nc "count(${MARK2}_value)"

echo "  -- 对 vmstorage 调 force_flush --"
curl -s -X POST --max-time 30 'http://localhost:8482/internal/force_flush' \
  -o /dev/null -w '    HTTP %{http_code}\n'
sleep 2
echo -n "  flush 后查: "
nc "count(${MARK2}_value)"

echo
echo "=============================================="
echo " F3 对照：单节点的 force_flush"
echo "=============================================="
curl -s -X POST --max-time 30 --data-binary @/tmp/l08_flush.influx \
  'http://localhost:8428/write' -o /dev/null
echo -n "  写入后立刻查: "
n1 "count(${MARK2}_value)"
curl -s -X POST --max-time 30 'http://localhost:8428/internal/force_flush' \
  -o /dev/null -w '    flush HTTP %{http_code}\n'
sleep 2
echo -n "  flush 后查: "
n1 "count(${MARK2}_value)"

echo
echo "=============================================="
echo " F4 集群各组件的角色自证：直接查 vmstorage 行不行"
echo "=============================================="
echo "  -- 直接查 vmstorage:8482 的查询接口 --"
curl -s --max-time 10 --data-urlencode 'query=count(l08_cluster_value)' \
  'http://localhost:8482/select/0/prometheus/api/v1/query' \
  -o /dev/null -w '    HTTP %{http_code} (vmstorage 不提供查询 API)\n' 2>&1
echo "  -- 直接往 vmstorage:8482 写 --"
curl -s -X POST --max-time 10 --data-binary @/tmp/l08_vis.influx \
  'http://localhost:8482/insert/0/influx/write' \
  -o /dev/null -w '    HTTP %{http_code} (vmstorage 不直接接受写入)\n' 2>&1
echo "  -- vmstorage 的 8482 提供什么 --"
curl -s --max-time 10 'http://localhost:8482/' 2>&1 | grep -oE '<a href="[^"]+"' | head -12

echo
echo "=============================================="
echo " F5 vminsert 的写入缓冲指标"
echo "=============================================="
curl -s --max-time 10 'http://localhost:8480/metrics' 2>/dev/null \
  | grep -E 'vm_insert_metrics|vm_rpc_|buffers' | head -10
