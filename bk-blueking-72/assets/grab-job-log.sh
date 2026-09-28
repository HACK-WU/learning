#!/usr/bin/env bash
# Job Pod 会被 controller 删，用高频轮询抢日志
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

kubectl delete job $J -n $NS --wait=false >/dev/null 2>&1
sleep 3
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
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
json.dump(d, open('/tmp/j8.json','w'))
PY
kubectl apply -f /tmp/j8.json -n $NS >/dev/null 2>&1
echo "Job 已创建，高频轮询抓日志..."

# 高频轮询，Pod 一出现就抓
for i in $(seq 1 120); do
  MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
  if [ -n "$MP" ]; then
    echo "  发现 Pod: $MP (第 ${i} 次轮询)"
    # 等它跑起来
    for j in $(seq 1 40); do
      PH=$(kubectl get pod $MP -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
      [ "$PH" != "Pending" ] && [ -n "$PH" ] && break
      sleep 2
    done
    echo "  phase=$PH"
    # 循环抓日志直到有内容或 Pod 消失
    for k in $(seq 1 60); do
      L=$(kubectl logs $MP -n $NS 2>&1)
      if echo "$L" | grep -qE 'Error|error|Exception|Traceback|No migrations|Operations to'; then
        echo "  ===== 抓到日志 ====="
        echo "$L" | grep -viE 'InsecureKeyLength|Deprecation|warnings.warn|_jws|return self' | tail -30 | sed 's/^/    /'
        exit 0
      fi
      sleep 2
    done
    echo "  未抓到有效日志"
    exit 1
  fi
  sleep 1
done
echo "  120s 内未发现 Pod"
