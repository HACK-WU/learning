#!/usr/bin/env bash
NS=blueking
echo "=== LINK ==="
kubectl get nodes --no-headers 2>&1 | awk '{print "  "$1" "$2}' | head -3
echo ""

# 收集所有 Service 的 selector，转成 "k=v,k=v" 串
kubectl get svc -n $NS -o json 2>/dev/null > /tmp/svc.json
echo "=== SVC COUNT ==="
python3 -c "
import json
d=json.load(open('/tmp/svc.json'))
print('  services:', len(d['items']))
" 2>&1 | sed 's/^/  /'
echo ""

# 对每个 deploy，检查是否有 svc 的 selector 是其 labels 的子集
kubectl get deploy -n $NS -o json 2>/dev/null > /tmp/dep.json
python3 - <<'PY'
import json
svcs=json.load(open('/tmp/svc.json'))['items']
deps=json.load(open('/tmp/dep.json'))['items']

def has_svc(labels):
    for s in svcs:
        sel=s['spec'].get('selector') or {}
        if not sel: continue
        if all(labels.get(k)==v for k,v in sel.items()):
            return s['metadata']['name']
    return None

front=[]; back=[]
for d in deps:
    n=d['metadata']['name']
    lbl=(d['spec']['template']['metadata'].get('labels') or {})
    # 补充 matchLabels
    ml=(d['spec'].get('selector',{}).get('matchLabels') or {})
    merged={**ml, **lbl}
    s=has_svc(merged)
    (front if s else back).append((n,s))

print("=== 有 Service（提供HTTP/被访问 = 影响页面） count=%d ==="%len(front))
for n,s in sorted(front): print("  %-46s <- svc:%s"%(n,s))
print("")
print("=== 无 Service（纯后台 = 可关候选） count=%d ==="%len(back))
for n,s in sorted(back): print("  %s"%n)
PY
