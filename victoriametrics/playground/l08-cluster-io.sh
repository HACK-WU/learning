#!/bin/bash
# 课 8 实验 1：集群写入与查询 —— 验证 URL 路径差异
# 单节点: http://localhost:8428/api/v1/write
# 集群  : http://localhost:8480/insert/0/prometheus/api/v1/write
#         http://localhost:8481/select/0/prometheus/api/v1/query
#                                     ↑
#                                 tenant ID (accountID)

echo "=============================================="
echo " W1 写入集群（注意 URL 里的 /insert/0/）"
echo "=============================================="
python3 - <<'PY'
import subprocess
now = int(subprocess.check_output(["date", "+%s"]).decode().strip())
start = now - 600          # ⚠️ 必须过去时间，课 6 踩过坑
lines = []
for i in range(100):
    ts = (start + i * 5) * 1000000000
    lines.append('l08_cluster,idx=%d value=%d.0 %d' % (i, i % 50, ts))
open("/tmp/l08_cluster.influx", "w").write("\n".join(lines) + "\n")
print("  生成 100 条样本（10 条序列 × 10 个时间点，过去时间）")
PY

echo
echo "  -- 集群写入端点 --"
curl -s -X POST --max-time 60 --data-binary @/tmp/l08_cluster.influx \
  'http://localhost:8480/insert/0/influx/write' \
  -o /dev/null -w '  HTTP: %{http_code}\n'

echo
echo "  -- 对照：单节点写入端点 --"
curl -s -X POST --max-time 60 --data-binary @/tmp/l08_cluster.influx \
  'http://localhost:8428/write' \
  -o /dev/null -w '  HTTP: %{http_code}\n'

sleep 3

echo
echo "=============================================="
echo " W2 从集群查询（注意 /select/0/）"
echo "=============================================="
echo "-- 集群: count(l08_cluster_value) --"
curl -s --max-time 30 --data-urlencode 'query=count(l08_cluster_value)' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
r=d.get("data",{}).get("result",[])
print("   序列数:", int(float(r[0]["value"][1])) if r else "无数据")' 2>&1

echo "-- 集群: 样本总数 --"
curl -s --max-time 30 --data-urlencode 'query=count_over_time(l08_cluster_value[1h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
r=d.get("data",{}).get("result",[])
print("   样本数:", int(sum(float(x["value"][1]) for x in r)) if r else "无数据")' 2>&1

echo
echo "=============================================="
echo " W3 关键验证：多租户隔离"
echo "=============================================="
echo "  tenant 0 有数据，tenant 1 应该没有"
for t in 0 1; do
  echo -n "  tenant $t: "
  curl -s --max-time 30 --data-urlencode 'query=count(l08_cluster_value)' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)
r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else 0, "条序列")' 2>&1
done

echo
echo "  -- 往 tenant 1 写点数据 --"
curl -s -X POST --max-time 60 --data-binary @/tmp/l08_cluster.influx \
  'http://localhost:8480/insert/1/influx/write' -o /dev/null -w '  HTTP: %{http_code}\n'
sleep 3
echo "  再看两个租户:"
for t in 0 1; do
  echo -n "    tenant $t: "
  curl -s --max-time 30 --data-urlencode 'query=count(l08_cluster_value)' \
    "http://localhost:8481/select/$t/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)
r=d.get("data",{}).get("result",[])
print(int(float(r[0]["value"][1])) if r else 0, "条序列")' 2>&1
done

echo
echo "=============================================="
echo " W4 单节点 vs 集群：URL 对照表验证"
echo "=============================================="
echo "  -- 单节点用集群的路径会怎样？--"
curl -s -o /dev/null -w '   单节点 /insert/0/prometheus/api/v1/write -> HTTP %{http_code}\n' \
  --max-time 10 -X POST --data-binary @/tmp/l08_cluster.influx \
  'http://localhost:8428/insert/0/prometheus/api/v1/write'
echo "  -- 集群用单节点的路径会怎样？--"
curl -s -o /dev/null -w '   集群(8480) /api/v1/write -> HTTP %{http_code}\n' \
  --max-time 10 -X POST --data-binary @/tmp/l08_cluster.influx \
  'http://localhost:8480/api/v1/write'
curl -s -o /dev/null -w '   集群(8481) /api/v1/query -> HTTP %{http_code}\n' \
  --max-time 10 --data-urlencode 'query=up' \
  'http://localhost:8481/api/v1/query'

echo
echo "=============================================="
echo " W5 vmui 入口对比"
echo "=============================================="
echo -n "  单节点 vmui (8428/vmui): "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 5 'http://localhost:8428/vmui'
echo -n "  集群 vmui (8481/select/0/vmui): "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 5 'http://localhost:8481/select/0/vmui'
