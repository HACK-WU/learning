#!/usr/bin/env bash
# 破死锁：让 paas3 绕过 APIGW 直连 IAM
# migrator.py:47-51 逻辑：BK_IAM_APIGATEWAY_URL 非空则优先用，置空后回落到 BK_IAM_V3_INNER_URL(200)
set -uo pipefail
NS=blueking
CM=bkpaas3-apiserver-general-envs

echo "===== 1. 备份 ConfigMap ====="
kubectl get cm $CM -n $NS -o yaml > /root/bk72/install/cm-$CM-$(date +%Y%m%d-%H%M%S).yaml 2>/dev/null
ls /root/bk72/install/cm-$CM-*.yaml 2>/dev/null | tail -1 | awk '{print "  备份: "$1}'

echo ""
echo "===== 2. 当前 IAM 相关键 ====="
kubectl get cm $CM -n $NS -o yaml 2>/dev/null | grep -iE 'IAM' | sed 's/^/  /'

echo ""
echo "===== 3. 置空 BK_IAM_APIGATEWAY_URL（触发回落）====="
kubectl patch cm $CM -n $NS --type merge -p '{"data":{"PAAS_BK_IAM_APIGATEWAY_URL":""}}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 确认已写入 ====="
kubectl get cm $CM -n $NS -o yaml 2>/dev/null | grep -iE 'APIGATEWAY_URL|V3_INNER' | sed 's/^/  /'

echo ""
echo "===== 5. 重启 paas3 相关负载使新 env 生效 ====="
for d in bkpaas3-apiserver-web bkpaas3-apiserver-worker; do
  kubectl rollout restart deployment/$d -n $NS 2>&1 | sed 's/^/  /'
done

echo ""
echo "===== 6. 重建 migrate-db Job（新 env）====="
J=bkpaas3-apiserver-migrate-db-1
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
kubectl delete job $J -n $NS --wait=false 2>&1 | sed 's/^/  /'
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
json.dump(d, open('/tmp/j5.json','w'))
PY
kubectl apply -f /tmp/j5.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 7. 等 90s 看 migrate 结果 ====="
sleep 90
kubectl get job $J -n $NS --no-headers 2>/dev/null | awk '{printf "  %-46s %-10s\n", $1, $2}'
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  echo "  --- $MP 日志 ---"
  kubectl logs $MP -n $NS 2>&1 | grep -viE 'InsecureKeyLength|Deprecation|warnings.warn|_jws' | tail -12 | sed 's/^/    /'
fi

echo ""
echo "===== 8. 卡 Init 的 Pod 复查 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'Init:' | awk '{printf "  %-48s %-16s\n", $1, $3}' | head -10
echo "  仍卡数: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -c 'Init:')"
