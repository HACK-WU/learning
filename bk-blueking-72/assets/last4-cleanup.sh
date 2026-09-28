#!/usr/bin/env bash
NS=blueking
echo "=== 缩回 0 ==="
for d in bkiam-saas-beat bkiam-saas-worker bk-apigateway-dashboard-beat bk-apigateway-dashboard-celery; do
  kubectl scale deploy -n $NS $d --replicas=0 >/dev/null 2>&1 && echo "  scaled $d -> 0"
done

sleep 45

echo ""
echo "=== 终态核验 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | awk '{print "    "$2" "$1}'
free -g | sed -n '2p' | awk '{printf "    内存 used=%sG avail=%sG\n",$3,$7}'
echo ""
echo "=== 未验证组件剩余（应为 0 个"从未验证"的） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print "    "$1}' | wc -l | xargs echo "    未起 deploy 总数:"
echo ""
echo "=== 探针残留终检 ==="
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); bad=0
for it in d['items']:
    for c in it['spec']['template']['spec']['containers']:
        lp=c.get('livenessProbe') or {}
        if lp.get('initialDelaySeconds')==180 or lp.get('failureThreshold')==12: bad+=1
print('    放宽值残留: %d'%bad)
"
echo ""
echo "=== 页面 ==="
for d in paas.example.com bkpaas.paas.example.com bkiam.paas.example.com; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "    %-28s %s\n" "$d" "$c"
done
