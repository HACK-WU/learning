#!/usr/bin/env bash
# 决定性对照：gossip 集群 vs 两个孤立 AM，通知条数差多少？
set -u
L8=/mnt/d/projects/learning/prometheus/labs/lesson-08

echo "############ 场景 A：gossip 集群（两副本互联）############"
echo "   （上一步已经跑过，当前 webhook 记录：）"
A=$(docker logs l8-webhook 2>&1 | grep -c '\[NOTIFY\]')
echo "   通知条数 = $A"

echo
echo "############ 场景 B：两个孤立 AM（拆散 gossip）############"
echo "   重建两个 AM，互不指定 --cluster.peer"
docker rm -f l8-am-1 l8-am-2 >/dev/null 2>&1 || true
docker rm -f l8-webhook >/dev/null 2>&1 || true
docker run -d --name l8-webhook --network l8net l8-webhook:latest >/dev/null

docker run -d --name l8-am-1 --network l8net -p 19120:9093 \
  -v "$L8/alertmanager-1.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:v0.30.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --cluster.listen-address=0.0.0.0:9094 >/dev/null

docker run -d --name l8-am-2 --network l8net -p 19121:9093 \
  -v "$L8/alertmanager-2.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:v0.30.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --cluster.listen-address=0.0.0.0:9094 >/dev/null

echo "   等待 20 秒..."
sleep 20

echo "   确认两个 AM 各自为政（peers=1 表示只有自己）："
for p in 19120 19121; do
  curl -s "http://localhost:$p/api/v2/status" | python -c "
import sys,json
d=json.load(sys.stdin)
c=d.get('cluster',{})
print(f\"   端口 $p: status={c.get('status')} peers={len(c.get('peers',[]))}\")
"
done

echo
echo "   向两个 AM 各发同一条告警..."
S=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
for p in 19120 19121; do
  curl -s -o /dev/null -XPOST "http://localhost:$p/api/v2/alerts" \
    -H "Content-Type: application/json" \
    -d "[{\"labels\":{\"alertname\":\"L8TestAlert\",\"severity\":\"warning\",\"idx\":\"0001\"},
          \"annotations\":{\"summary\":\"课8测试告警\"},\"startsAt\":\"$S\"}]"
done

echo "   等待 25 秒..."
sleep 25

B=$(docker logs l8-webhook 2>&1 | grep -c '\[NOTIFY\]')
echo "   通知条数 = $B"

echo
echo "############ 决定性结论 ############"
echo "   gossip 集群（两副本互联）: $A 条通知"
echo "   孤立双副本（无 gossip）  : $B 条通知"
echo
if [ "$B" -gt "$A" ]; then
  echo "   --> gossip 确实消除了重复通知（$B 条 -> $A 条）"
else
  echo "   --> 两者相同，需要重新设计实验（可能是告警内容/时序问题）"
fi
