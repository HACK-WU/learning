#!/bin/bash
# 课 9 排查：RF=2 写入后，为什么两个节点的副本数不一样？
# 现象：写入 200 条序列，vmstorage1 只有 101 条，vmstorage2 有 200 条
# 方法：给每个 vmstorage 单独接一个 vmselect，直接看各节点存了什么
set -u
NET=vm-cluster-net
VER=v1.151.0-cluster

q() {
  curl -s --max-time 60 --data-urlencode "query=$1" \
    "http://localhost:$2/select/0/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}

echo "=============================================="
echo " P0 端口 8485/8486 是否空闲"
echo "=============================================="
for p in 8485 8486; do
  r=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://localhost:$p/health" 2>/dev/null)
  echo "  port $p -> HTTP $r"
done

echo
echo "=============================================="
echo " P1 启动两个专用 vmselect（各只连一个 vmstorage）"
echo "=============================================="
docker rm -f vmsel-n1 vmsel-n2 >/dev/null 2>&1
docker run -d --name vmsel-n1 --network "$NET" -p 8485:8481 \
  "victoriametrics/vmselect:$VER" \
  -storageNode=vmstorage-learn:8401 -httpListenAddr=:8481 >/dev/null 2>&1
docker run -d --name vmsel-n2 --network "$NET" -p 8486:8481 \
  "victoriametrics/vmselect:$VER" \
  -storageNode=vmstorage-learn2:8401 -httpListenAddr=:8481 >/dev/null 2>&1

for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8485/health' 2>/dev/null)
  b=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8486/health' 2>/dev/null)
  if [ "$a" = "200" ] && [ "$b" = "200" ]; then echo "  两个专用 vmselect 就绪"; break; fi
  sleep 2
done

echo
echo "=============================================="
echo " P2 各节点实际存了多少 l09_rf2"
echo "=============================================="
echo "  vmstorage1 (8485): $(q 'count_over_time(l09_rf2_value[1h])' 8485)"
echo "  vmstorage2 (8486): $(q 'count_over_time(l09_rf2_value[1h])' 8486)"
echo "  集群聚合 (8481):   $(q 'count_over_time(l09_rf2_value[1h])' 8481)"

echo
echo "=============================================="
echo " P3 vminsert 指标与日志"
echo "=============================================="
curl -s --max-time 15 'http://localhost:8480/metrics' 2>/dev/null \
  | grep -iE 'rerout|replic|rows_(sent|dropped|pushed)|errors' | head -20
echo
echo "  -- vminsert 日志尾部 --"
docker logs vminsert-learn 2>&1 | tail -5

echo
echo "=============================================="
echo " P4 重新写入一批，观察这次是否完整复制"
echo "=============================================="
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
lines = ["l09_rf3,idx=%d value=%d %d" % (i, i, ts) for i in range(200)]
open("/tmp/l09_rf3.influx","w").write("\n".join(lines)+"\n")
print("  生成 l09_rf3: 200 条序列")
PY
curl -s -X POST --max-time 60 --data-binary @/tmp/l09_rf3.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'

echo "  等待 15 秒..."
sleep 15

echo "  vmstorage1 (8485): $(q 'count_over_time(l09_rf3_value[1h])' 8485)"
echo "  vmstorage2 (8486): $(q 'count_over_time(l09_rf3_value[1h])' 8486)"
echo "  集群聚合 (8481):   $(q 'count_over_time(l09_rf3_value[1h])' 8481)"
echo
echo "  → 若两节点都是 200，说明 RF=2 正常，之前的 101 是瞬时问题"

echo
echo "=============================================="
echo " P5 vmselect 的 dedup 参数是否存在"
echo "=============================================="
docker run --rm "victoriametrics/vmselect:$VER" --help 2>&1 \
  | grep -iB1 -A3 'dedup' | head -25
