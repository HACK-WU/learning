#!/bin/bash
# 课 9 实验 1：给 vminsert 配置复制因子 -replicationFactor=2
set -u
NET=vm-cluster-net
VER=v1.151.0-cluster

echo "=============================================="
echo " R0 配置前基线（课 8 遗留，无副本）"
echo "=============================================="
echo -n "  vmstorage1 tsid: "
curl -s --max-time 15 'http://localhost:8482/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'
echo -n "  vmstorage2 tsid: "
curl -s --max-time 15 'http://localhost:8492/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'

echo
echo "=============================================="
echo " R1 重启 vminsert，加上 -replicationFactor=2"
echo "=============================================="
echo "  ⚠️ replicationFactor 是【启动时】参数，必须重启 vminsert"
docker rm -f vminsert-learn >/dev/null 2>&1 && echo "  已删除旧 vminsert"

docker run -d --name vminsert-learn \
  --network "$NET" -p 8480:8480 \
  "victoriametrics/vminsert:$VER" \
  -storageNode=vmstorage-learn:8400 \
  -storageNode=vmstorage-learn2:8400 \
  -replicationFactor=2 \
  -httpListenAddr=:8480 2>&1 | tail -1

echo "  等待就绪..."
for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8480/health' 2>/dev/null)
  if [ "$a" = "200" ]; then echo "  vminsert 就绪（第 ${i}×2 秒）"; break; fi
  sleep 2
done

echo
echo "  -- vminsert 日志：确认复制因子生效 --"
docker logs vminsert-learn 2>&1 | tail -8

echo
echo "=============================================="
echo " R2 写入一批带副本的数据"
echo "=============================================="
python3 - <<'PY'
import time
now = int(time.time())
ts = (now - 120) * 1000000000   # 过去 120 秒
lines = ["l09_rf2,idx=%d value=%d %d" % (i, i, ts) for i in range(200)]
open("/tmp/l09_rf2.influx","w").write("\n".join(lines)+"\n")
print("  生成 200 条序列（l09_rf2），时间戳 = 过去 120 秒")
PY

B1=$(curl -s --max-time 15 'http://localhost:8482/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')
B2=$(curl -s --max-time 15 'http://localhost:8492/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')
echo "  写入前: vmstorage1=$B1  vmstorage2=$B2"

curl -s -X POST --max-time 60 --data-binary @/tmp/l09_rf2.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'

sleep 6

A1=$(curl -s --max-time 15 'http://localhost:8482/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')
A2=$(curl -s --max-time 15 'http://localhost:8492/metrics' 2>/dev/null | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')

echo "  写入后: vmstorage1=$A1  vmstorage2=$A2"
echo "  增量:   vmstorage1=+$((A1-B1))  vmstorage2=+$((A2-B2))"
echo
echo "  → 如果【两个节点都增加了 200】，说明每条数据存了两份"

echo
echo "=============================================="
echo " R3 查询：副本会带来重复数据吗？"
echo "=============================================="
echo "  vmselect 当前参数（无 dedup）:"
docker inspect vmselect-learn --format '  {{.Args}}' 2>&1

echo
echo "  -- count(l09_rf2_value) 应该返回多少？--"
curl -s --max-time 60 --data-urlencode 'query=count(l09_rf2_value)' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     count =", int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo "  -- 用 count_over_time 看样本数 --"
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l09_rf2_value[1h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("     样本数 =", int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo
echo "  ⚠️ 期望：如果没配 dedup，200 条序列 × 2 副本 = 400 个样本"

echo
echo "=============================================="
echo " R4 关键：停掉一个节点，有副本后数据还全吗？"
echo "=============================================="
echo "  -- 先记录全量结果 --"
echo -n "    两节点都在 count_over_time: "
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l09_rf2_value[1h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "  停掉 vmstorage-learn2 ..."
docker stop vmstorage-learn2 >/dev/null 2>&1
sleep 5
echo -n "    只剩一个节点 count_over_time: "
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l09_rf2_value[1h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo "  恢复 vmstorage-learn2 ..."
docker start vmstorage-learn2 >/dev/null 2>&1
sleep 8
echo -n "    恢复后 count_over_time: "
curl -s --max-time 60 --data-urlencode 'query=count_over_time(l09_rf2_value[1h])' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else "空")' 2>&1

echo
echo "  → 对比课 8：无副本时停节点会【静默少一半】"
echo "    有副本时应该【数据完整】"
