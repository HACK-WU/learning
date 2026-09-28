#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. bkiam-api ingress 完整规则（所有 path）====="
kubectl get ingress bkiam -n $NS -o jsonpath='{range .spec.rules[*]}{"  host: "}{.host}{"\n"}{range .http.paths[*]}{"    path="}{.path}{"  type="}{.pathType}{"  svc="}{.backend.service.name}{":"}{.backend.service.port.number}{.backend.service.port.name}{"\n"}{end}{end}' 2>&1

echo ""
echo "===== 2. bkiam-saas ingress 完整规则 ====="
kubectl get ingress bkiam-saas -n $NS -o jsonpath='{range .spec.rules[*]}{"  host: "}{.host}{"\n"}{range .http.paths[*]}{"    path="}{.path}{"  svc="}{.backend.service.name}{":"}{.backend.service.port.number}{.backend.service.port.name}{"\n"}{end}{end}' 2>&1

echo ""
echo "===== 3. IAM 后端真实 svc 清单 ====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -iE 'bkiam' | awk '{printf "  %-34s %-12s %s\n", $1, $2, $5}'

echo ""
echo "===== 4. 关键：bkiam-web 和 bkiam-saas-api 谁有 /ping ====="
echo "  --- bkiam-web:80/ping ---"
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '    HTTP %{http_code}\n' --max-time 8 http://bkiam-web.blueking.svc.cluster.local/ping" 2>&1
echo "  --- bkiam-saas-api:80/ping ---"
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '    HTTP %{http_code}\n' --max-time 8 http://bkiam-saas-api.blueking.svc.cluster.local/ping" 2>&1

echo ""
echo "===== 5. IAM SDK 的 api_ping 到底请求什么路径 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'python -c "
import inspect
from iam.contrib.iam_migration import migrator as m
src = inspect.getsource(m)
import re
for i,l in enumerate(src.splitlines()):
    if \"ping\" in l.lower() or \"api_ping\" in l.lower():
        print(f\"    {i}: {l.strip()[:110]}\")
"' 2>&1 | head -12

echo ""
echo "===== 6. 看 do_migrate.api_ping 实现 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'find /usr/local/lib/python3.11/site-packages/iam -name "*.py" | xargs grep -ln "api_ping" 2>/dev/null | head -3' 2>&1 | sed 's/^/    /'
kubectl exec paas3-dbg -n $NS -- bash -c 'grep -rn "def api_ping" -A 12 /usr/local/lib/python3.11/site-packages/iam/contrib/iam_migration/*.py 2>/dev/null | head -18' 2>&1 | sed 's/^/    /'
