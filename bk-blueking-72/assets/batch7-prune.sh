#!/usr/bin/env bash
NS=blueking

echo "=== 1. 裁前：24 个组件状态 ==="
ok=0
while read l; do
  st=$(echo $l|awk '{print $2}'); [ "$st" = "1/1" ] && ok=$((ok+1))
done < <(kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -E 'bk-monitor-(alarm|web-worker-resource)')
echo "    就绪 $ok / 24"

echo ""
echo "=== 2. 裁前留证：核心业务证据 ==="
echo "  [beat 调度]"
kubectl logs -n $NS $(kubectl get pod -n $NS --no-headers|grep '^bk-monitor-alarm-beat-'|head -1|awk '{print $1}') --tail=20 2>&1 | grep 'Sending due' | tail -1 | cut -c1-150 | sed 's/^/      /'
echo "  [alert 选主]"
kubectl logs -n $NS $(kubectl get pod -n $NS --no-headers|grep '^bk-monitor-alarm-alert-'|head -1|awk '{print $1}') --tail=20 2>&1 | grep 'elected to be leader' | tail -1 | cut -c1-150 | sed 's/^/      /'
echo "  [worker 连 rabbitmq]"
kubectl logs -n $NS $(kubectl get pod -n $NS --no-headers|grep '^bk-monitor-alarm-converge-worker-'|head -1|awk '{print $1}') --tail=20 2>&1 | grep 'Connected to amqp' | tail -1 | cut -c1-140 | sed 's/^/      /'
echo "  [策略数]"
kubectl exec -n $NS $(kubectl get pod -n $NS --no-headers|grep '^bk-monitor-alarm-detect-'|head -1|awk '{print $1}') -- \
  python -c "
import django,os
os.environ.setdefault('DJANGO_SETTINGS_MODULE','settings'); django.setup()
from bkmonitor.models import StrategyModel
print('      Strategy 总数:', StrategyModel.objects.count())
" 2>&1 | grep Strategy

echo ""
echo "=== 3. 裁前内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== 4. 裁掉告警链路 24 个 ==="
for d in $(kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -E 'bk-monitor-(alarm|web-worker-resource)' | awk '{print $1}'); do
  kubectl scale deploy -n $NS $d --replicas=0 >/dev/null 2>&1
done
echo "    已 scale 0"

echo ""
echo "=== 5. 等 100s ==="
sleep 100
free -g | sed -n '2p' | awk '{printf "    裁后 used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== 6. 集群健康 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -4

echo ""
echo "=== 7. 页面复查 ==="
for d in paas.example.com bkpaas.paas.example.com bkiam.paas.example.com bknodeman.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "    %-28s %s\n" "$d" "$code"
done
