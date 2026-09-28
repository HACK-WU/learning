#!/usr/bin/env bash
NS=blueking

echo "=== 1. 内存基线 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== 2. 24 个组件：资源 + 探针（按 liveness init 升序，激进的排前面） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' \
| grep -E 'bk-monitor-(alarm|web-worker-resource)' | while read d; do
  kubectl get deploy -n $NS $d -o json 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except: sys.exit()
c=d['spec']['template']['spec']['containers'][0]
r=c.get('resources',{}); req=r.get('requests',{}); lim=r.get('limits',{})
lp=c.get('livenessProbe') or {}
rp=c.get('readinessProbe') or {}
li=lp.get('initialDelaySeconds',999)
print('%s|%s|%s|%s|%s' % (li,
  d['metadata']['name'].replace('bk-monitor-',''),
  req.get('memory','-'), lim.get('memory','-'),
  rp.get('initialDelaySeconds','无')))
" 2>/dev/null
done | sort -t'|' -k1 -n | awk -F'|' '{
  init=($1==999?"无":$1"s")
  printf "  %-38s live_init=%-5s ready=%-4s req=%-7s lim=%-7s\n",$2,init,$5,$3,$4}'

echo ""
echo "=== 3. 告警链路依赖（influxdb/transfer/kafka/redis） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null \
  | grep -iE 'bk-influxdb|transfer|bk-kafka-0|bk-redis|bk-mysql8-0|bk-mongodb-0|bk-monitor-(api|healthz|unify-query)' \
  | awk '{printf "    %-46s %s\n",$1,$3}' | head -12

echo ""
echo "=== 4. 告警链路 svc（看有没有独立入口） ==="
kubectl get svc -n $NS 2>/dev/null | grep -E 'monitor' | awk '{print "    "$1" "$5}' | head -12
