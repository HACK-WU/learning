#!/usr/bin/env bash
NS=blueking

echo "=== STEP 1: 起 logstash（sts，1-2Gi 内存） ==="
kubectl scale sts -n $NS bk-applog-bkapp-logstash --replicas=1 >/dev/null 2>&1 && echo "  [起] logstash (initialDelay 已默认 300s)"
sleep 60
kubectl get sts -n $NS bk-applog-bkapp-logstash --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n",$1,$2}'

echo ""
echo "=== STEP 2: 等 180s（logstash 是 JVM，启动慢） ==="
sleep 180
kubectl get pods -n $NS --no-headers 2>/dev/null | grep logstash | awk '{print "  "$1" "$3}'

echo ""
echo "=== STEP 3: 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 4: filebeat 状态（logstash 起来后应有变化） ==="
kubectl get ds -n $NS --no-headers 2>/dev/null | grep filebeat | awk '{printf "  %-46s ready=%s\n",$1,$4}'
