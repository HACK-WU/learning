#!/usr/bin/env bash
NS=blueking
echo "=== STEP 1: 裁前留证 —— 告警链路最终状态 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-' > /tmp/alarm-before.txt
echo "  告警组件数: $(wc -l < /tmp/alarm-before.txt)"
echo "  全部 Ready: $(awk '$2==$3' /tmp/alarm-before.txt | wc -l) / $(wc -l < /tmp/alarm-before.txt)"
cat /tmp/alarm-before.txt | awk '{printf "    %-46s %s\n",$1,$2}'

echo ""
echo "=== STEP 2: 裁前留证 —— kafka 消费组（证明告警链路真在消费） ==="
kubectl exec -n $NS bk-kafka-0 -- kafka-consumer-groups.sh --list --bootstrap-server localhost:9092 2>&1 | grep -E 'bkmonitorv3' | head -8 | sed 's/^/    /'
echo "    总计: $(kubectl exec -n $NS bk-kafka-0 -- kafka-consumer-groups.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep -c bkmonitorv3) 个"

echo ""
echo "=== STEP 3: 裁前内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 4: 裁掉告警链路 ==="
for d in $(awk '{print $1}' /tmp/alarm-before.txt); do
  kubectl scale deploy -n $NS $d --replicas=0 >/dev/null 2>&1
done
echo "  已 scale 0: $(awk '{print $1}' /tmp/alarm-before.txt | wc -l) 个"

echo ""
echo "=== STEP 5: 等 90s 回收 ==="
sleep 90
free -g | sed -n '2p' | awk '{printf "    裁后 used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 6: 确认核心链路仍健在 ==="
for d in bk-monitor-web bk-monitor-web-query-api bk-monitor-api bk-monitor-unify-query bk-monitor-ingester bk-monitor-transfer-default bk-monitor-influxdb-proxy bk-monitor-grafana; do
  kubectl get deploy -n $NS $d --no-headers 2>/dev/null | awk '{printf "    %-40s %s\n",$1,$2}'
done

echo ""
echo "=== STEP 7: 监控页面仍可访问 ==="
curl -s -o /dev/null -w '    bkmonitor.paas.example.com -> %{http_code}\n' --max-time 10 http://bkmonitor.paas.example.com/
