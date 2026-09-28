#!/usr/bin/env bash
echo "=== 1. 各命名空间 Pod 数与内存 requests 汇总 ==="
for ns in blueking monitoring kube-system calico-system tigera-operator ingress-nginx default local-path-storage envoy-gateway-system bkpaas-app-operator-system; do
  out=$(kubectl get pods -n $ns --no-headers 2>/dev/null)
  cnt=$(echo "$out" | grep -c . )
  [ "$cnt" -eq 0 ] && continue
  mem=$(kubectl get pods -n $ns -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); t=0
def p(m):
    try:
        if m.endswith('Gi'): return float(m[:-2])*1024
        if m.endswith('Mi'): return float(m[:-2])
        if m.endswith('Ki'): return float(m[:-2])/1024
    except: pass
    return 0
for it in d['items']:
    for c in it['spec'].get('containers',[]):
        t+=p((c.get('resources',{}).get('requests',{}) or {}).get('memory',''))
print('%.2f'%(t/1024))
" 2>/dev/null)
  printf "  %-28s Pod=%-4s reqMem=%s Gi\n" "$ns" "$cnt" "$mem"
done

echo ""
echo "=== 2. monitoring 命名空间明细（历史遗留？） ==="
kubectl get pods -n monitoring --no-headers 2>/dev/null | head -12 | sed 's/^/  /'

echo ""
echo "=== 3. 非 blueking 的 Deployment（历史课程遗留） ==="
kubectl get deploy -A --no-headers 2>/dev/null | awk '$1!="blueking"{print "  "$1" "$2}' | head -25

echo ""
echo "=== 4. 其他 kind 集群（也在吃内存） ==="
docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | sed 's/^/  /'
