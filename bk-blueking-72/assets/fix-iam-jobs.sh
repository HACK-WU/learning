#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 重建两个 Failed 的 iam Job 并抢日志 ====="
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
for J in bkiam-saas-apigateway-sync-1 bkiam-saas-synchronization-1; do
  echo "  ============ $J ============"
  kubectl delete job $J -n $NS --wait=false >/dev/null 2>&1
  sleep 2
  python3 - "$BAK/$J.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    d['metadata'].pop(k, None)
d.pop('status', None)
s=d['spec']; s.pop('selector',None); s['backoffLimit']=1
s.pop('ttlSecondsAfterFinished',None)
t=s['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']: t.pop(k,None)
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid',None)
    t['labels'].pop('controller-uid',None)
json.dump(d, open('/tmp/ij.json','w'))
PY
  kubectl apply -f /tmp/ij.json -n $NS >/dev/null 2>&1
  # 抢日志
  for i in $(seq 1 60); do
    MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
    if [ -n "$MP" ]; then
      for k in $(seq 1 40); do
        L=$(kubectl logs $MP -n $NS 2>&1)
        echo "$L" | grep -qE 'Error|error|Exception|Traceback' && {
          echo "$L" | grep -viE 'InsecureKey|Deprecat|warnings.warn' | tail -14 | sed 's/^/    /'
          break 2
        }
        sleep 2
      done
      break
    fi
    sleep 1
  done
  echo ""
done

echo "===== 2. paas3 卡 Init 的 init 容器名与状态 ====="
P=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-web' | grep 'Init:' | awk '{print $1}' | head -1)
echo "  Pod: $P"
kubectl get pod $P -n $NS -o jsonpath='{range .status.initContainerStatuses[*]}    {.name}  ready={.ready}  reason={.state.waiting.reason}  msg={.state.waiting.message}{"\n"}{end}' 2>&1
echo ""
echo "  init 容器日志:"
IN=$(kubectl get pod $P -n $NS -o jsonpath='{.status.initContainerStatuses[0].name}' 2>/dev/null)
kubectl logs $P -n $NS -c $IN --tail=20 2>&1 | sed 's/^/    /'

echo ""
echo "===== 3. check-migrate-db 在等什么（看它的 command）====="
BAKP=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
kubectl get deployment bkpaas3-apiserver-web -n $NS -o jsonpath='{range .spec.template.spec.initContainers[*]}    [{.name}] cmd={.command} args={.args}{"\n"}{end}' 2>&1
