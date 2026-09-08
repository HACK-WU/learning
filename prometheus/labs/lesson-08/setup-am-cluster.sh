#!/usr/bin/env bash
# Alertmanager gossip 集群 + webhook 接收器（完整版）
set -u
L8=/mnt/d/projects/learning/prometheus/labs/lesson-08

echo "=== 0. 起 webhook 接收器（接入 l8net）==="
docker rm -f l8-webhook >/dev/null 2>&1 || true
docker build -q -t l8-webhook:latest -f "$L8/app/Dockerfile.webhook" "$L8/app"
docker run -d --name l8-webhook --network l8net l8-webhook:latest >/dev/null

echo "=== 1. 起两个 Alertmanager 组成 gossip 集群 ==="
docker rm -f l8-am-1 l8-am-2 >/dev/null 2>&1 || true

docker run -d --name l8-am-1 --network l8net -p 19120:9093 \
  -v "$L8/alertmanager-1.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:v0.30.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --cluster.listen-address=0.0.0.0:9094 \
  --cluster.peer=l8-am-2:9094 >/dev/null

docker run -d --name l8-am-2 --network l8net -p 19121:9093 \
  -v "$L8/alertmanager-2.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager:v0.30.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --cluster.listen-address=0.0.0.0:9094 \
  --cluster.peer=l8-am-1:9094 >/dev/null

echo "   等待 20 秒让 gossip 建立..."
sleep 20

echo
echo "=== 2. gossip 集群状态 ==="
for p in 19120 19121; do
  curl -s "http://localhost:$p/api/v2/status" | python -c "
import sys,json
d=json.load(sys.stdin)
c=d.get('cluster',{})
peers=c.get('peers',[])
print(f\"   端口 $p: status={c.get('status')}  peers={len(peers)}\")
for pp in peers:
    print(f\"      peer {pp.get('name')} @ {pp.get('address')}\")
"
done

echo
echo "=== 3. 清空 webhook 记录 ==="
docker exec l8-webhook wget -qO- http://localhost:8080/reset >/dev/null 2>&1 || true

echo
echo "=== 4. 向两个 AM 各发一条相同告警（模拟 HA 双推）==="
S=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
for p in 19120 19121; do
  curl -s -o /dev/null -w "   发给 $p: HTTP %{http_code}\n" \
    -XPOST "http://localhost:$p/api/v2/alerts" \
    -H "Content-Type: application/json" \
    -d "[{
          \"labels\": {\"alertname\":\"L8TestAlert\",\"severity\":\"warning\",\"idx\":\"0001\"},
          \"annotations\": {\"summary\":\"课8测试告警\"},
          \"startsAt\": \"$S\"
        }]"
done

echo
echo "   等待 25 秒（group_wait=5s + group_interval=10s，留足余量）..."
sleep 25

echo
echo "=== 5. 关键：webhook 收到几条通知？ ==="
N=$(docker exec l8-webhook wget -qO- http://localhost:8080/count 2>/dev/null | tr -d '\n')
echo "   收到通知数 = ${N:-?}"
echo
echo "   判读："
echo "     2 条 = 两个 AM 各发了一遍（gossip 未生效 / 未同步通知日志）"
echo "     1 条 = gossip 同步了通知日志，只有一条真正发出（预期）"
echo
echo "=== 6. webhook 收到的内容 ==="
docker exec l8-webhook cat /data/notifications.jsonl 2>/dev/null | python -c "
import sys,json
for line in sys.stdin:
    r=json.loads(line)
    print(f\"   status={r['status']} alerts={len(r['alerts'])} commonLabels={r['commonLabels']}\")
"
