#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 看 migrator.py:73 到底 ping 哪个地址 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'sed -n "55,80p" /app/paasng/infras/iam/bkpaas_iam_migration/migrator.py' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 2. IAM 相关配置全量 ====="
kubectl exec paas3-dbg -n $NS -- env 2>/dev/null | grep -iE 'IAM' | grep -iE 'URL|HOST|ADDR|API' | sed 's/^/    /'

echo ""
echo "===== 3. 逐个实测候选地址 ====="
for u in "http://bkiam.paas.example.com/ping" "http://bkiam-api.paas.example.com/ping" "http://bkiam-api.paas.example.com/api/v1/ping" "http://bkiam.paas.example.com/api/v1/ping"; do
  C=$(kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 8 '$u'" 2>/dev/null)
  echo "  ${C:-000}  $u"
done

echo ""
echo "===== 4. 检查 iam sdk 的实际配置来源 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'grep -rn "IAM_V3_INNER\|BK_IAM_URL\|iam_host\|IAM_HOST" /app/paasng/settings/*.py 2>/dev/null | head -10' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 5. 直接调 iam ping 看返回体（可能是 200 但内容不对）====="
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 'http://bkiam.paas.example.com/ping' | head -c 300" 2>&1 | sed 's/^/    /'
echo ""
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 -i 'http://bkiam-api.paas.example.com/' | head -12" 2>&1 | sed 's/^/    /'

echo ""
echo "===== 6. ingress 上 bkiam-api 的路由是否存在 ====="
kubectl get ingress -n $NS -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.rules[*]}    host={.host} path={.http.paths[0].path} svc={.http.paths[0].backend.service.name}{"\n"}{end}{end}' 2>/dev/null | grep -E 'bkiam|apigw' | sed 's/^/  /'
