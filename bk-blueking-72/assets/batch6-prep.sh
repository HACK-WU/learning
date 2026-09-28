#!/usr/bin/env bash
NS=blueking

echo "=== 1. 内存基线 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== 2. nodeman 7 个组件：资源 + 探针 ==="
for d in bk-nodeman-backend-celery-beat bk-nodeman-backend-common-pworker \
         bk-nodeman-backend-common-worker bk-nodeman-backend-sync-host \
         bk-nodeman-backend-sync-host-re bk-nodeman-backend-sync-process \
         bk-nodeman-backend-sync-watch; do
  kubectl get deploy -n $NS $d -o json 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except: print('  [读取失败]'); sys.exit()
c=d['spec']['template']['spec']['containers'][0]
r=c.get('resources',{})
req=r.get('requests',{}); lim=r.get('limits',{})
lp=c.get('livenessProbe') or {}
rp=c.get('readinessProbe') or {}
print('  %-40s req_mem=%-6s lim_mem=%-6s live_init=%-4s ready_init=%s' % (
    d['metadata']['name'][:40],
    req.get('memory','-'), lim.get('memory','-'),
    lp.get('initialDelaySeconds','无'), rp.get('initialDelaySeconds','无')))
" 2>&1
done

echo ""
echo "=== 3. nodeman 依赖（mysql/mongodb/redis/gse） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -iE 'bk-mysql8|bk-mongodb|bk-redis-master|gse|bk-gse' | awk '{printf "  %-44s %s\n",$1,$3}'

echo ""
echo "=== 4. nodeman 的 svc / ingress ==="
kubectl get svc -n $NS 2>/dev/null | grep nodeman | awk '{print "  svc  "$1" "$5}'
kubectl get ingress -n $NS 2>/dev/null | grep -i nodeman | awk '{print "  ing  "$2" "$3}'
