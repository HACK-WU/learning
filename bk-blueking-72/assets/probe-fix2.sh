#!/usr/bin/env bash
NS=blueking
echo "=== 把 failureThreshold 从 12 还原为原始 5 ==="
for d in bk-repo-bkrepo-auth bk-repo-bkrepo-docker bk-repo-bkrepo-gateway bk-repo-bkrepo-helm \
         bk-repo-bkrepo-job bk-repo-bkrepo-maven bk-repo-bkrepo-npm bk-repo-bkrepo-opdata \
         bk-repo-bkrepo-pypi bk-repo-bkrepo-replication bk-repo-bkrepo-repository; do
  kubectl patch deploy -n $NS $d --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":5}]' \
    >/dev/null 2>&1 && echo "  OK  $d" || echo "  FAIL $d"
done

echo ""
echo "=== 复核：还有没有 init=180 或 fail=12 的残留 ==="
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); bad=[]
for it in d['items']:
    n=it['metadata']['name']
    for i,c in enumerate(it['spec']['template']['spec']['containers']):
        lp=c.get('livenessProbe') or {}
        if lp.get('initialDelaySeconds')==180 or lp.get('failureThreshold')==12:
            bad.append('%s init=%s fail=%s'%(n,lp.get('initialDelaySeconds'),lp.get('failureThreshold')))
print('  残留 %d 个'%len(bad))
for b in bad: print('    '+b)
"

echo ""
echo "=== 终态：探针与原始值对照 ==="
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for it in sorted(d['items'],key=lambda x:x['metadata']['name']):
    n=it['metadata']['name']
    if not n.startswith('bk-repo-'): continue
    c=it['spec']['template']['spec']['containers'][0]
    lp=c.get('livenessProbe') or {}
    print('  %-30s init=%-5s fail=%-3s period=%s'%(n,lp.get('initialDelaySeconds'),lp.get('failureThreshold'),lp.get('periodSeconds')))
"
