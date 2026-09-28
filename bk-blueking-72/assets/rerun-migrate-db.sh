#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)

echo "===== 1. 删旧 Job 并从备份重建（无 status 污染）====="
kubectl delete job $J -n $NS --wait=false 2>&1 | sed 's/^/  /'
sleep 3
python3 - "$BAK/$J.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    d['metadata'].pop(k, None)
d.pop('status', None)
s=d['spec']
s.pop('selector',None)
s['backoffLimit']=0          # 一次就够，失败立刻留 Pod
s.pop('ttlSecondsAfterFinished',None)
t=s['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']: t.pop(k,None)
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid',None)
    t['labels'].pop('controller-uid',None)
json.dump(d, open('/tmp/j4.json','w'))
print("  已生成 /tmp/j4.json")
PY
kubectl apply -f /tmp/j4.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 轮询等 Pod 出现（最多 90s）====="
MP=""
for i in $(seq 1 18); do
  MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
  [ -n "$MP" ] && break
  sleep 5
done
if [ -z "$MP" ]; then echo "  90s 内无 Pod，退出"; exit 1; fi
echo "  Pod: $MP"

echo ""
echo "===== 3. 等它跑完（最多 180s），然后抓日志 ====="
for i in $(seq 1 36); do
  S=$(kubectl get pod $MP -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Succeeded" ] || [ "$S" = "Failed" ] && break
  sleep 5
done
echo "  终态: $(kubectl get pod $MP -n $NS -o jsonpath='{.status.phase}')"

echo ""
echo "===== 4. 完整日志（找 IAM ping 之后的新报错）====="
kubectl logs $MP -n $NS 2>&1 | grep -viE 'InsecureKeyLength|DeprecationWarning|warnings.warn|return self._jws' | tail -35 | sed 's/^/    /'
