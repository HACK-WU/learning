#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 根因：bk iam ping error —— 看 bk-iam Pod 状态 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bk-iam|bkiam' | awk '{printf "  %-46s %-16s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 2. bk-iam 的 svc 和 endpoint（有没有后端）====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -E 'bk-iam|bkiam' | awk '{printf "  %-36s %-14s %s\n", $1, $2, $5}'
echo "  --- endpoints ---"
kubectl get endpoints -n $NS --no-headers 2>/dev/null | grep -E 'bk-iam|bkiam' | awk '{printf "  %-40s %s\n", $1, $2}'

echo ""
echo "===== 3. paas3 里配置的 IAM 地址 ====="
kubectl exec paas3-dbg -n $NS -- env 2>/dev/null | grep -iE 'PAAS_IAM|IAM_|BK_IAM' | sed 's/^/    /' | head -15

echo ""
echo "===== 4. 从 paas3 Pod 实测 ping bk-iam ====="
IAM_HOST=$(kubectl exec paas3-dbg -n $NS -- env 2>/dev/null | grep -iE 'PAAS_IAM_BASE_URL|BK_IAM_URL|IAM_BASE_URL' | head -1 | cut -d= -f2-)
echo "  IAM地址: $IAM_HOST"
kubectl exec paas3-dbg -n $NS -- bash -c "curl -s -o /dev/null -w '  HTTP %{http_code}  耗时%{time_total}s\n' --max-time 10 '${IAM_HOST}/ping' 2>&1" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. bk-iam 服务日志 ====="
for d in bk-iam-backend bkiam-backend bk-iam-apigateway; do
  if kubectl get deploy $d -n $NS >/dev/null 2>&1; then
    echo "  --- $d ---"
    kubectl logs -n $NS deploy/$d 2>&1 | tail -8 | sed 's/^/    /'
  fi
done

echo ""
echo "===== 6. bk-iam 的 migration 有没有完成（IAM 模型没注册会导致 ping 失败）====="
kubectl get jobs -n $NS --no-headers 2>/dev/null | grep -iE 'iam' | awk '{printf "  %-46s %-10s\n", $1, $2}'
