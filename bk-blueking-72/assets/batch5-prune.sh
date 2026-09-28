#!/usr/bin/env bash
NS=blueking
EP=$(kubectl get secret -n $NS bk-elastic-elasticsearch -o jsonpath='{.data.elasticsearch-password}' 2>/dev/null | base64 -d 2>/dev/null)

echo "=== STEP 1: 裁前留证 —— 日志链路组件 ==="
echo "  [sts] $(kubectl get sts -n $NS bk-applog-bkapp-logstash --no-headers 2>/dev/null | awk '{print $1" "$2}')"
kubectl get ds -n $NS --no-headers 2>/dev/null | grep filebeat | awk '{printf "  [ds]  %-46s ready=%s\n",$1,$4}'

echo ""
echo "=== STEP 2: 裁前留证 —— 端到端证据 ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s -u "elastic:$EP" --max-time 12 'http://127.0.0.1:9200/_cat/indices?v' 2>&1 \
  | grep -E "$(date +%Y.%m.%d)" | awk '{printf "    %-44s docs=%s\n",$3,$7}'

echo ""
echo "=== STEP 3: 裁前内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 4: 裁掉 logstash ==="
kubectl scale sts -n $NS bk-applog-bkapp-logstash --replicas=0 >/dev/null 2>&1
echo "  logstash -> 0"

echo ""
echo "=== STEP 5: 等 90s 回收 ==="
sleep 90
free -g | sed -n '2p' | awk '{printf "    裁后 used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 6: 集群健康 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -4

echo ""
echo "=== STEP 7: 核心页面复查 ==="
for d in paas.example.com bkpaas.paas.example.com bkiam.paas.example.com bkuser.paas.example.com apigw.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "    %-30s %s\n" "$d" "$code"
done

echo ""
echo "=== STEP 8: 剩余未验证组件总数 ==="
echo "  deploy 0/0: $(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
echo "  sts    0/0: $(kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
