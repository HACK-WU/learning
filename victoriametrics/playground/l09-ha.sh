#!/bin/bash
# 课 9 知识点 3：高可用部署与故障演练
# 核心命题：RF=2 + dedup，能否真的扛住节点故障？
set -u

q() {
  curl -s --max-time 60 --data-urlencode "query=$1" \
    "http://localhost:$2/select/0/prometheus/api/v1/query" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
}

echo "=============================================="
echo " H0 准备一份【完整副本】的测试数据"
echo "=============================================="
echo "  等集群稳定..."
sleep 10
M="l09_ha_$(date +%s)"
python3 - "$M" <<'PY'
import sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 120) * 1000000000
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(300)]
open("/tmp/l09_ha.influx","w").write("\n".join(lines)+"\n")
print("  序列: %s (300 条)" % mark)
PY
BEFORE_ERR=$(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy')
curl -s -X POST --max-time 60 --data-binary @/tmp/l09_ha.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'
sleep 12
AFTER_ERR=$(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy')

Q="count_over_time(${M}_value[1h])"
echo "  vmstorage1: $(q "$Q" 8485)"
echo "  vmstorage2: $(q "$Q" 8486)"
echo "  集群(无dedup 8481): $(q "$Q" 8481)"
echo "  集群(有dedup 8487): $(q "$Q" 8487)"
echo "  本次写入副本失败次数: $((AFTER_ERR-BEFORE_ERR))"

echo
echo "=============================================="
echo " H1 故障演练：停掉一个 vmstorage"
echo "=============================================="
echo "  ⚠️ 与课 8 的对照实验（课 8 无副本：1000 → 509，静默少一半）"
echo
echo "  停止前:"
echo "    无 dedup: $(q "$Q" 8481)"
echo "    有 dedup: $(q "$Q" 8487)"

echo
echo "  停掉 vmstorage-learn2 ..."
docker stop vmstorage-learn2 >/dev/null 2>&1
sleep 8

echo "  停止后:"
echo "    无 dedup: $(q "$Q" 8481)"
echo "    有 dedup: $(q "$Q" 8487)"
echo
echo "  → 有副本 + dedup，应该【仍是 300】，与课 8 的 509 形成鲜明对比"

echo
echo "=============================================="
echo " H2 故障期间写入：副本会怎样？"
echo "=============================================="
M2="l09_ha2_$(date +%s)"
python3 - "$M2" <<'PY'
import sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 60) * 1000000000
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(100)]
open("/tmp/l09_ha2.influx","w").write("\n".join(lines)+"\n")
print("  故障期间写入 %s (100 条)" % mark)
PY
E1=$(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy')
curl -s -X POST --max-time 60 --data-binary @/tmp/l09_ha2.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w '  HTTP %{http_code}\n'
sleep 6
E2=$(docker logs vminsert-learn 2>&1 | grep -c 'cannot make a copy')
echo "  副本失败新增: $((E2-E1)) 次"
echo
echo "  -- vminsert 日志（副本失败的具体提示）--"
docker logs vminsert-learn 2>&1 | grep 'cannot make a copy' | tail -3

echo
echo "=============================================="
echo " H3 恢复节点：故障期间的数据能补回来吗？"
echo "=============================================="
echo "  启动 vmstorage-learn2 ..."
docker start vmstorage-learn2 >/dev/null 2>&1
echo "  等待 25 秒（让节点完全恢复）..."
sleep 25

echo
echo "  恢复后:"
echo "    H1 数据(有dedup): $(q "$Q" 8487)"
echo "    H1 数据(无dedup): $(q "$Q" 8481)"
Q2="count_over_time(${M2}_value[1h])"
echo "    H2 故障期数据(有dedup): $(q "$Q2" 8487)"
echo "    H2 故障期数据(无dedup): $(q "$Q2" 8481)"
echo
echo "  → 关键问题：故障期间只写了 1 份的数据，恢复后会不会自动补成 2 份？"

echo
echo "=============================================="
echo " H4 答案：VictoriaMetrics 不自动补副本"
echo "=============================================="
echo "  -- 分别查两个节点上 H2 数据的份数 --"
echo "      vmstorage1(8485): $(q "$Q2" 8485)"
echo "      vmstorage2(8486): $(q "$Q2" 8486)"
echo
if [ "$(q "$Q2" 8485)" = "100" ] && [ "$(q "$Q2" 8486)" = "100" ]; then
  echo "      ✅ 两节点都有 → 自动补齐了"
else
  echo "      ⚠️ 只有部分节点有 → 副本缺口【不会自动补】"
  echo "         这意味着该批数据目前只有 1 份，再丢一次就永久丢失"
fi

echo
echo "=============================================="
echo " H5 多副本 + 多 vminsert 的高可用写法"
echo "=============================================="
echo "  -- 启动第二个 vminsert（端口 8488）--"
docker rm -f vminsert-learn2 >/dev/null 2>&1
docker run -d --name vminsert-learn2 \
  --network vm-cluster-net -p 8488:8480 \
  victoriametrics/vminsert:v1.151.0-cluster \
  -storageNode=vmstorage-learn:8400 \
  -storageNode=vmstorage-learn2:8400 \
  -replicationFactor=2 \
  -httpListenAddr=:8480 >/dev/null 2>&1
for i in $(seq 1 30); do
  a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8488/health' 2>/dev/null)
  if [ "$a" = "200" ]; then echo "  第二个 vminsert 就绪 (8488)"; break; fi
  sleep 2
done

echo
echo "  -- 通过第二个 vminsert 写入，验证都能用 --"
M3="l09_ha3_$(date +%s)"
python3 - "$M3" <<'PY'
import sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 60) * 1000000000
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(50)]
open("/tmp/l09_ha3.influx","w").write("\n".join(lines)+"\n")
PY
curl -s -X POST --max-time 60 --data-binary @/tmp/l09_ha3.influx \
  'http://localhost:8488/insert/0/influx/write' -o /dev/null -w '  经 vminsert2(8488) 写入 HTTP %{http_code}\n'
sleep 8
Q3="count_over_time(${M3}_value[1h])"
echo "    节点1: $(q "$Q3" 8485)  节点2: $(q "$Q3" 8486)  聚合(dedup): $(q "$Q3" 8487)"

echo
echo "=============================================="
echo " H6 组件级高可用总结"
echo "=============================================="
echo "  -- 停掉 vminsert-learn，用 vminsert-learn2 写入 --"
docker stop vminsert-learn >/dev/null 2>&1
sleep 3
M4="l09_ha4_$(date +%s)"
python3 - "$M4" <<'PY'
import sys, time
mark = sys.argv[1]
ts = (int(time.time()) - 60) * 1000000000
lines = ["%s,idx=%d value=%d %d" % (mark, i, i, ts) for i in range(30)]
open("/tmp/l09_ha4.influx","w").write("\n".join(lines)+"\n")
PY
echo -n "  经 vminsert(8480, 已停) 写入: "
curl -s -X POST --max-time 10 --data-binary @/tmp/l09_ha4.influx \
  'http://localhost:8480/insert/0/influx/write' -o /dev/null -w 'HTTP %{http_code}\n'
echo -n "  经 vminsert2(8488) 写入: "
curl -s -X POST --max-time 30 --data-binary @/tmp/l09_ha4.influx \
  'http://localhost:8488/insert/0/influx/write' -o /dev/null -w 'HTTP %{http_code}\n'
echo "  → 多个 vminsert 前置负载均衡即可实现写入高可用"
docker start vminsert-learn >/dev/null 2>&1
sleep 5
echo "  vminsert-learn 已恢复"
