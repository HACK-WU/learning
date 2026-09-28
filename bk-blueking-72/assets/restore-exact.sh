#!/usr/bin/env bash
NS=blueking

echo "=== kafka 完整原值（liveness + readiness） ==="
helm get manifest bk-kafka -n $NS 2>/dev/null | python3 -c "
import sys,yaml
docs=list(yaml.safe_load_all(sys.stdin))
for d in docs:
    if not d or d.get('kind')!='StatefulSet': continue
    if d['metadata']['name']!='bk-kafka': continue
    c=d['spec']['template']['spec']['containers'][0]
    print('  liveness :', c.get('livenessProbe'))
    print('  readiness:', c.get('readinessProbe'))
" 2>&1

echo ""
echo "=== bkrepo 完整原值（取 auth 作样本） ==="
helm get manifest bk-repo -n $NS 2>/dev/null | python3 -c "
import sys,yaml
docs=list(yaml.safe_load_all(sys.stdin))
seen=set()
for d in docs:
    if not d or d.get('kind')!='Deployment': continue
    n=d['metadata']['name']
    if not n.startswith('bk-repo-bkrepo-'): continue
    c=d['spec']['template']['spec']['containers'][0]
    lp=c.get('livenessProbe'); rp=c.get('readinessProbe')
    key=(str(lp),str(rp))
    if key in seen: continue
    seen.add(key)
    print(' ',n)
    print('    liveness :', lp)
    print('    readiness:', rp)
" 2>&1

echo ""
echo "=== generic 是否有探针（我记的是无） ==="
helm get manifest bk-repo -n $NS 2>/dev/null | python3 -c "
import sys,yaml
docs=list(yaml.safe_load_all(sys.stdin))
for d in docs:
    if not d or d.get('kind')!='Deployment': continue
    if d['metadata']['name']!='bk-repo-bkrepo-generic': continue
    c=d['spec']['template']['spec']['containers'][0]
    print('    liveness :', c.get('livenessProbe'))
    print('    readiness:', c.get('readinessProbe'))
" 2>&1
