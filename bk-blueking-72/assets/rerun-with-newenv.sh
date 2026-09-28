#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. 删掉所有旧 paas3 卡 Init 的 Pod（让它们重建吃新 env）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3' | grep 'Init:' | awk '{print $1}' | while read p; do
  kubectl delete pod $p -n $NS --wait=false 2>&1 | sed 's/^/  /'
done

echo ""
echo "===== 2. 重建 migrate-db Job ====="
kubectl delete job $J -n $NS --wait=false 2>&1 | sed 's/^/  /'
sleep 3
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
python3 - "$BAK/$J.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    d['metadata'].pop(k, None)
d.pop('status', None)
s=d['spec']; s.pop('selector',None); s['backoffLimit']=3
s.pop('ttlSecondsAfterFinished',None)
t=s['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']: t.pop(k,None)
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid',None)
    t['labels'].pop('controller-uid',None)
json.dump(d, open('/tmp/j7.json','w'))
PY
kubectl apply -f /tmp/j7.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 轮询 Job 状态（最多 150s）====="
for i in $(seq 1 30); do
  ST=$(kubectl get job $J -n $NS -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
  FL=$(kubectl get job $J -n $NS -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
  [ "$ST" = "True" ] && { echo "  ✅ Job Complete"; break; }
  [ "$FL" = "True" ] && { echo "  ❌ Job Failed"; break; }
  sleep 5
done
kubectl get job $J -n $NS --no-headers 2>/dev/null | awk '{printf "  %-46s %-10s\n", $1, $2}'

echo ""
echo "===== 4. 全局异常 Pod 复查 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-48s %-18s 重启%s\n", $1, $3, $4}' | head -12
echo "  ---"
echo "  总 Pod: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"
echo "  异常数: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l)"
echo "  卡 Init: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -c 'Init:')"
