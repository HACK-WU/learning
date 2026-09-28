#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. Job 现状（看 status 是不是带过来的）====="
kubectl get job $J -n $NS -o jsonpath='{range .status}{"  succeeded: "}{.succeeded}{"  failed: "}{.failed}{"  active: "}{.active}{"\n"}{end}' 2>&1
kubectl get job $J -n $NS --no-headers 2>/dev/null | awk '{printf "  %-46s %-10s\n", $1, $2}'

echo ""
echo "===== 2. 是否已有 completion 记录（导致不再调度）====="
kubectl get job $J -n $NS -o jsonpath='{.status.completionTime}' 2>&1 | sed 's/^/  completionTime: /'
echo ""
kubectl get job $J -n $NS -o jsonpath='{.status.conditions[*].type}' 2>&1 | sed 's/^/  conditions: /'
echo ""

echo ""
echo "===== 3. 换个名重建（避开残留状态）====="
kubectl get job $J -n $NS -o json > /tmp/j2.json 2>/dev/null
python3 - <<'PY'
import json
d = json.load(open('/tmp/j2.json'))
m = d['metadata']
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    m.pop(k, None)
m['name'] = 'paas3-migrate-probe'
d.pop('status', None)
s = d['spec']
s.pop('selector', None)
s['backoffLimit'] = 1
s.pop('ttlSecondsAfterFinished', None)
t = s['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']:
    t.pop(k, None)
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid', None)
    t['labels'].pop('controller-uid', None)
    t['labels']['job-name'] = 'paas3-migrate-probe'
json.dump(d, open('/tmp/j2-new.json','w'))
print("  改名 paas3-migrate-probe")
PY
kubectl apply -f /tmp/j2-new.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 等 30s ====="
sleep 30
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'paas3-migrate-probe' | awk '{printf "  %-46s %-14s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 5. 真实日志 ====="
P=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'paas3-migrate-probe' | awk '{print $1}' | head -1)
if [ -n "$P" ]; then
  echo "  Pod: $P"
  kubectl logs $P -n $NS --tail=50 2>&1 | sed 's/^/    /'
else
  echo "  仍无 Pod"
  kubectl describe job paas3-migrate-probe -n $NS 2>&1 | tail -15 | sed 's/^/    /'
fi
