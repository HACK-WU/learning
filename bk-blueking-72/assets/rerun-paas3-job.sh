#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)

echo "===== 1. 重建 paas3 migrate-db Job ====="
kubectl delete job $J -n $NS --wait=false >/dev/null 2>&1
sleep 3
python3 - "$BAK/$J.yaml" <<'PY'
import json,sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in ['uid','resourceVersion','creationTimestamp','generation','managedFields','ownerReferences','selfLink','namespace','annotations']:
    d['metadata'].pop(k, None)
d.pop('status', None)
s=d['spec']; s.pop('selector',None); s['backoffLimit']=2
s.pop('ttlSecondsAfterFinished',None)
t=s['template']['metadata']
for k in ['creationTimestamp','managedFields','ownerReferences']: t.pop(k,None)
if 'labels' in t:
    t['labels'].pop('batch.kubernetes.io/controller-uid',None)
    t['labels'].pop('controller-uid',None)
json.dump(d, open('/tmp/jf.json','w'))
PY
kubectl apply -f /tmp/jf.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 等 Job 完成（最多 300s）====="
for i in $(seq 1 100); do
  S=$(kubectl get job $J -n $NS -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
  [ "$S" = "Complete" ] && { echo "  ✅ Complete (第${i}轮)"; break; }
  [ "$S" = "Failed" ] && { echo "  ❌ Failed"; break; }
  sleep 3
done
kubectl get job $J -n $NS --no-headers 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 如果失败，抓 bkrepo-init 日志 ====="
if [ "$S" = "Failed" ]; then
  MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
  [ -n "$MP" ] && kubectl logs $MP -n $NS -c apiserver-bkrepo-init --tail=20 2>&1 | sed 's/^/    /'
fi

echo ""
echo "===== 4. 等 paas3 Pod 脱离 Init（最多 180s）====="
for i in $(seq 1 60); do
  C=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -c 'Init:')
  [ "$C" = "0" ] && { echo "  ✅ 无 Pod 卡 Init (第${i}轮)"; break; }
  sleep 3
done

echo ""
echo "===== 5. 全局异常 Pod ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-52s %-20s 重启%s\n", $1, $3, $4}'
echo "  --- 总 Pod: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)  异常: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l) ---"
