#!/usr/bin/env bash
set -uo pipefail
NS=blueking
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. 找 migrate-db 的 Pod（可能已保留）====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{printf "  %-48s %-12s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 2. 抓日志（先看新 Pod）====="
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep "^$J" | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  echo "  Pod: $MP"
  kubectl logs $MP -n $NS 2>&1 | grep -viE 'InsecureKeyLength|Deprecation|warnings.warn|_jws|return self' | tail -25 | sed 's/^/    /'
else
  echo "  无 Pod 保留，用 describe 看 Job 事件"
  kubectl describe job $J -n $NS 2>&1 | tail -12 | sed 's/^/    /'
fi

echo ""
echo "===== 3. 关键：新起的 Pod 里 BK_IAM_APIGATEWAY_URL 实际值 ====="
NP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkpaas3-apiserver-web' | grep -v 'db9949744' | awk '{print $1}' | head -1)
echo "  检查 web Pod: $NP"
kubectl exec $NP -n $NS -- env 2>/dev/null | grep -iE 'BK_IAM_APIGATEWAY|BK_IAM_V3_INNER' | sed 's/^/    /'

echo ""
echo "===== 4. 用诊断 Pod 模拟：置空后 api_ping 走哪个地址 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'cd /app && BK_IAM_APIGATEWAY_URL="" python -c "
import django, os
os.environ[\"PAAS_BK_IAM_APIGATEWAY_URL\"]=\"\"
os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\",\"paasng.settings\")
django.setup()
from django.conf import settings
from paasng.infras.iam.bkpaas_iam_migration import migrator
import inspect
src=inspect.getsource(migrator)
print(\"--- migrator 关键行 ---\")
for i,l in enumerate(src.splitlines()[40:60],41):
    print(f\"  {i}: {l}\")
" 2>&1 | grep -viE "warning|deprecat"' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 5. 直接测：回落后的地址能不能 ping 通 ====="
echo "  bkiam-api.paas.example.com/ping:"
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 http://bkiam-api.paas.example.com/ping | head -c 120" 2>&1 | sed 's/^/    /'
echo ""
echo "  该地址需要能响应 IAM 的 API（不只是 pong）:"
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s --max-time 8 -o /dev/null -w '    /api/v1/model/system/ HTTP %{http_code}\n' http://bkiam-api.paas.example.com/api/v1/model/system/" 2>&1
