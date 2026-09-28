#!/usr/bin/env bash
echo "=== 1. 节点内存水位（Allocatable vs 已分配） ==="
kubectl describe nodes 2>/dev/null | grep -A5 -E '^Allocated resources' | head -30 | sed 's/^/  /'

echo ""
echo "=== 2. 各节点实际 requests 汇总 ==="
kubectl get nodes --no-headers -o custom-columns='NAME:.metadata.name' 2>/dev/null | while read n; do
  m=$(kubectl describe node $n 2>/dev/null | grep -A6 'Allocated resources' | grep 'memory' | head -1)
  echo "  $n : $m"
done

echo ""
echo "=== 3. blueking 内存 requests TOP20（真正的瘦身目标） ==="
kubectl get pods -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
def p(m):
    try:
        if m.endswith('Gi'): return float(m[:-2])*1024
        if m.endswith('Mi'): return float(m[:-2])
        if m.endswith('Ki'): return float(m[:-2])/1024
    except: pass
    return 0
rows=[]
for it in d['items']:
    n=it['metadata']['name']
    ph=it['status'].get('phase','')
    if ph in ('Succeeded','Failed'): continue
    t=sum(p((c.get('resources',{}).get('requests',{}) or {}).get('memory','')) for c in it['spec'].get('containers',[]))
    if t>0: rows.append((n,t,ph))
rows.sort(key=lambda x:-x[1])
print('  %-58s %-9s %s'%('POD','REQ-MEM','PHASE'))
for n,t,ph in rows[:20]:
    print('  %-58s %-9s %s'%(n[:58],'%.0fMi'%t,ph))
print('  ...')
print('  合计(req，仅Running/Pending): %.2f Gi'%(sum(x[1] for x in rows)/1024))
"

echo ""
echo "=== 4. Terminating Pod 的 requests（卡住未释放的量） ==="
kubectl get pods -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
def p(m):
    try:
        if m.endswith('Gi'): return float(m[:-2])*1024
        if m.endswith('Mi'): return float(m[:-2])
    except: pass
    return 0
t=0;n=0
for it in d['items']:
    if it['status'].get('phase')=='Running' and it['metadata'].get('deletionTimestamp'):
        n+=1
        t+=sum(p((c.get('resources',{}).get('requests',{}) or {}).get('memory','')) for c in it['spec'].get('containers',[]))
print('  Terminating 中仍 Running 的: %d 个, 共 %.2f Gi'%(n,t/1024))
"
