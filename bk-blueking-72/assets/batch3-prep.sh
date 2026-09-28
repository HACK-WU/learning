#!/usr/bin/env bash
NS=blueking
echo "=== 1. 内存 ==="
free -g | sed -n '1,2p' | sed 's/^/  /'

echo ""
echo "=== 2. 节点 ==="
kubectl get nodes --no-headers 2>&1 | sed 's/^/  /'

echo ""
echo "=== 3. kafka 探针配置（当前值） ==="
kubectl get sts -n $NS bk-kafka -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
print('  container:', c.get('name'))
for p in ('livenessProbe','readinessProbe'):
    print('  %s: %s' % (p, json.dumps(c.get(p),ensure_ascii=False)))
" 2>&1 | sed 's/^/  /'

echo ""
echo "=== 4. 监控相关 deploy 当前副本 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep 'bk-monitor' | awk '{printf "  %-52s %s\n",$1,$2}' | head -45

echo ""
echo "=== 5. influxdb-proxy Init 容器状态 ==="
kubectl get pod -n $NS bk-monitor-influxdb-proxy-76f888568f-xvh79 -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for ic in d['spec'].get('initContainers',[]): print('  init:',ic.get('name'),ic.get('image'))
for s in d['status'].get('initContainerStatuses',[]):
    print('  status:',s['name'],s['state'])
" 2>&1 | sed 's/^/  /'
