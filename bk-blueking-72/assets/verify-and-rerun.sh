#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. HTTP 连通性实测（关键域名）====="
for d in bkiam.paas.example.com bkapi.paas.example.com bkrepo.example.com; do
  R=$(kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://$d/ping" 2>/dev/null)
  echo "  $d -> HTTP ${R:-000}"
done

echo ""
echo "===== 2. 重跑 paas3 migrate-db（IAM ping 现在应该通了）====="
kubectl delete job bkpaas3-apiserver-migrate-db-1 -n $NS --wait=false 2>&1 | sed 's/^/  /'
sleep 2
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
python3 - "$BAK/bkpaas3-apiserver-migrate-db-1.yaml" <<'PY'
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
json.dump(d, open('/tmp/j3.json','w'))
PY
kubectl apply -f /tmp/j3.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 重跑两个 CrashLoop 的 iam Job ====="
for j in bkiam-saas-apigateway-sync-1 bkiam-saas-synchronization-1; do
  for p in $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$j" | awk '{print $1}'); do
    kubectl delete pod $p -n $NS --wait=false 2>&1 | sed 's/^/  删除 /'
  done
done

echo ""
echo "===== 4. 等 60s 看结果 ====="
sleep 60
echo "  --- paas3 migrate-db ---"
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-migrate-db' | awk '{printf "    %-46s %-12s 重启%s\n", $1, $3, $4}'
echo "  --- iam sync ---"
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkiam-saas' | grep -E 'sync|synchron' | awk '{printf "    %-46s %-16s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 5. 全局异常 Pod 复查 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -vE 'Running|Completed' | awk '{printf "  %-46s %-18s 重启%s\n", $1, $3, $4}' | head -15
echo "  （空=全部正常）"
echo "  总计: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l) 个 Pod"
