#!/usr/bin/env bash
NS=blueking
echo "=== 1. cmdb 相关 Pod ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep cmdb | head -20

echo ""
echo "=== 2. cmdb ingress / svc ==="
kubectl get ingress -n $NS 2>/dev/null | grep -i cmdb
kubectl get svc -n $NS 2>/dev/null | grep -i cmdb

echo ""
echo "=== 3. cmdb web 是否存在（蓝鲸 cmdb 可能没有独立 web） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{print $1}' | grep cmdb

echo ""
echo "=== 4. nginx-ingress 是否健在 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -i nginx | head -5

echo ""
echo "=== 5. 内存 TOP 15 ==="
kubectl top pod -n $NS --no-headers 2>/dev/null | sort -k3 -h -r | head -15 | awk '{printf "  %-56s %s\n",$1,$3}'

echo ""
echo "=== 6. 谁在吃内存（按前缀聚合） ==="
kubectl top pod -n $NS --no-headers 2>/dev/null | python3 -c "
import sys,collections
agg=collections.defaultdict(int)
for line in sys.stdin:
    p=line.split()
    if len(p)<3: continue
    name,mem=p[0],p[2]
    v=float(mem[:-2]) if mem.endswith('Mi') else (float(mem[:-2])*1024 if mem.endswith('Gi') else 0)
    key='-'.join(name.split('-')[:3])
    agg[key]+=v
for k,v in sorted(agg.items(),key=lambda x:-x[1])[:12]:
    print('  %-44s %6.0f Mi'%(k,v))
"
