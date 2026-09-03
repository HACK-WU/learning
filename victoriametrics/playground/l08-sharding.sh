#!/bin/bash
# 课 8 核心实验：扩到 2 个 vmstorage，验证一致性哈希分片
# 观察：1) 数据是否均匀分散  2) 查询是否聚合两个节点  3) 扩容后数据是否重分布

set -u
NET=vm-cluster-net
VER=v1.151.0-cluster
DATA=/mnt/d/projects/learning/victoriametrics/playground/cluster-data

echo "=============================================="
echo " H0 扩容前：单 vmstorage 的基线"
echo "=============================================="
echo -n "  vmstorage-learn 序列数: "
curl -s --max-time 20 'http://localhost:8482/metrics' 2>/dev/null \
  | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}'

echo
echo "=============================================="
echo " H1 启动第二个 vmstorage"
echo "=============================================="
mkdir -p "$DATA/storage2"
docker run -d --name vmstorage-learn2 \
  --network "$NET" \
  -p 8492:8482 -p 8410:8400 -p 8411:8401 \
  -v "$DATA/storage2:/storage" \
  "victoriametrics/vmstorage:$VER" \
  -storageDataPath=/storage \
  -retentionPeriod=1d \
  -vminsertAddr=:8400 \
  -vmselectAddr=:8401 \
  -httpListenAddr=:8482 \
  2>&1 | tail -1

echo "  等待就绪..."
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8492/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmstorage2 就绪"; break; fi
  sleep 2
done

echo
echo "=============================================="
echo " H2 重启 vminsert / vmselect，让它们知道新节点"
echo "=============================================="
echo "  ⚠️ 这是集群扩容的关键步骤：-storageNode 是【启动时】读的，"
echo "     社区版不支持热发现（企业版才支持）"

docker rm -f vminsert-learn vmselect-learn >/dev/null 2>&1
echo "  已删除旧的 vminsert / vmselect"

docker run -d --name vminsert-learn \
  --network "$NET" -p 8480:8480 \
  "victoriametrics/vminsert:$VER" \
  -storageNode=vmstorage-learn:8400 \
  -storageNode=vmstorage-learn2:8400 \
  -httpListenAddr=:8480 2>&1 | tail -1

docker run -d --name vmselect-learn \
  --network "$NET" -p 8481:8481 \
  "victoriametrics/vmselect:$VER" \
  -storageNode=vmstorage-learn:8401 \
  -storageNode=vmstorage-learn2:8401 \
  -httpListenAddr=:8481 2>&1 | tail -1

echo "  等待就绪..."
for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8480/health' 2>/dev/null)
  b=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8481/health' 2>/dev/null)
  if [ "$a" = "200" ] && [ "$b" = "200" ]; then echo "  全部就绪"; break; fi
  sleep 2
done

echo
echo "  -- vminsert 日志：确认连上了两个节点 --"
docker logs vminsert-learn 2>&1 | grep -c 'successfully dialed' | awk '{print "     dialed 次数:", $1}'

echo
echo "=============================================="
echo " H3 写入一批新数据，观察分片"
echo "=============================================="
python3 - <<'PY'
import time
now = int(time.time())
lines = []
# 1000 条序列，每条 1 个点，落在过去 5 分钟内
for i in range(1000):
    ts = (now - 120) * 1000000000
    lines.append("l08_shard,idx=%d value=%d %d" % (i, i, ts))
open("/tmp/l08_shard.influx","w").write("\n".join(lines)+"\n")
print("  生成 1000 条序列")
PY
curl -s -X POST --max-time 120 --data-binary @/tmp/l08_shard.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'

sleep 8

echo
echo "=============================================="
echo " H4 分片结果：两个 vmstorage 各分到多少"
echo "=============================================="
for pair in "vmstorage-learn:8482" "vmstorage-learn2:8492"; do
  name="${pair%%:*}"; port="${pair##*:}"
  n=$(curl -s --max-time 20 "http://localhost:$port/metrics" 2>/dev/null \
      | grep 'vm_cache_entries{type="storage/tsid"' | head -1 | awk '{print $2}')
  echo "  $name (port $port): tsid 条目 = ${n:-0}"
done

echo
echo "  -- 用查询验证：vmselect 聚合了两个节点的数据 --"
curl -s --max-time 60 --data-urlencode 'query=count(l08_shard_value)' \
  'http://localhost:8481/select/0/prometheus/api/v1/query' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print("    vmselect 聚合结果:", int(float(r[0]["value"][1])) if r else "空")' 2>&1

echo
echo "  -- 分别直连两个 vmstorage 查（用 vmselect 的单节点查询能力）--"
echo "     ⚠️ vmstorage 不提供查询 API，只能通过 vmselect 查"
echo "     改用指标对比：看各节点的 rows_inserted"

echo
echo "=============================================="
echo " H5 分片均匀度分析"
echo "=============================================="
for pair in "vmstorage-learn:8482" "vmstorage-learn2:8492"; do
  name="${pair%%:*}"; port="${pair##*:}"
  echo "  -- $name --"
  curl -s --max-time 20 "http://localhost:$port/metrics" 2>/dev/null \
    | grep -E 'vm_new_timeseries_created_total|vm_rows_inserted_total\{type="influx"|vm_rows{type="influx"' \
    | head -3
done
