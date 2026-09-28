#!/usr/bin/env bash
# 修正：真正的开关是 BK_IAM_USE_APIGATEWAY（不是 APIGATEWAY_URL）
# 源码 migrator.py:44-51
#   use_apigateway=True  -> 用 BK_IAM_APIGATEWAY_URL（bkapi，404）
#   use_apigateway=False -> 用 BK_IAM_V3_INNER_URL（bkiam-api，pong 200）
set -uo pipefail
NS=blueking
CM=bkpaas3-apiserver-general-envs

echo "===== 1. 回滚我上一版的无效改动 ====="
kubectl patch cm $CM -n $NS --type merge -p '{"data":{"PAAS_BK_IAM_APIGATEWAY_URL":"http://bkapi.paas.example.com/api/bk-iam/prod"}}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 改真正的开关：关闭 USE_APIGATEWAY ====="
kubectl patch cm $CM -n $NS --type merge -p '{"data":{"PAAS_BK_IAM_USE_APIGATEWAY":"false"}}' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 确认 ====="
kubectl get cm $CM -n $NS -o yaml 2>/dev/null | grep -iE 'USE_APIGATEWAY|APIGATEWAY_URL|V3_INNER' | sed 's/^/  /'

echo ""
echo "===== 4. 重建 migrate-db Job（吃新 env）====="
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
json.dump(d, open('/tmp/j6.json','w'))
PY
kubectl apply -f /tmp/j6.json -n $NS 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 立刻建一个探针 Pod 验证 env 是否生效 ====="
kubectl delete pod paas3-iam-probe -n $NS --wait=false 2>/dev/null >/dev/null
kubectl run paas3-iam-probe -n $NS --restart=Never --image=hub.bktencent.com/blueking/paas3-apiserver:v1.6.0-beta.32 \
  --env="PAAS_BK_IAM_USE_APIGATEWAY=false" \
  --command -- sleep 600 2>&1 | sed 's/^/  /'
sleep 15
kubectl exec paas3-iam-probe -n $NS -- env 2>/dev/null | grep -iE 'USE_APIGATEWAY' | sed 's/^/    /'

echo ""
echo "===== 6. 等 Job 结果（120s）====="
sleep 100
kubectl get job $J -n $NS --no-headers 2>/dev/null | awk '{printf "  %-46s %-10s\n", $1, $2}'
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  echo "  --- 日志 ---"
  kubectl logs $MP -n $NS 2>&1 | grep -viE 'InsecureKeyLength|Deprecation|warnings.warn|_jws|return self' | tail -18 | sed 's/^/    /'
fi

echo ""
echo "===== 7. 卡 Init 复查 ====="
echo "  仍卡 Init: $(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -c 'Init:')"
