#!/usr/bin/env bash
NS=blueking
echo "=== 内存 TOP 20 ==="
kubectl top pod -n $NS --no-headers 2>/dev/null | sort -k3 -h -r | head -20 | awk '{printf "  %-58s %s\n",$1,$3}'

echo ""
echo "=== 按模块聚合 ==="
kubectl top pod -n $NS --no-headers 2>/dev/null | python3 -c "
import sys,collections
agg=collections.defaultdict(int)
for line in sys.stdin:
    p=line.split()
    if len(p)<3: continue
    name,mem=p[0],p[2]
    try:
        v=float(mem[:-2]) if mem.endswith('Mi') else (float(mem[:-2])*1024 if mem.endswith('Gi') else 0)
    except: continue
    key='-'.join(name.split('-')[:3])
    agg[key]+=v
tot=sum(agg.values())
for k,v in sorted(agg.items(),key=lambda x:-x[1])[:14]:
    print('  %-46s %7.0f Mi'%(k,v))
print('  %-46s %7.0f Mi'%('=== TOTAL ===',tot))
"

echo ""
echo "=== 系统内存 ==="
free -g | sed -n '1,2p'

echo ""
echo "=== 非 blueking 命名空间的 Running Pod 数 ==="
for n in monitoring kube-system; do
  echo "  $n: $(kubectl get pods -n $n --no-headers 2>/dev/null | awk '$3==\"Running\"' | wc -l) running"
done
