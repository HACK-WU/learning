#!/usr/bin/env bash
set -uo pipefail
NS=blueking
MP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-mysql8' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. bk_login 库里的用户（登录实际校验处）====="
[ -n "$MP" ] && kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SELECT username, is_superuser FROM bk_login.login_user LIMIT 10;" 2>/dev/null | sed 's/^/    /'

echo ""
echo "===== 2. bk_user_api 库里的用户 ====="
[ -n "$MP" ] && kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SHOW TABLES FROM bk_user_api;" 2>/dev/null | head -12 | sed 's/^/    /'

echo ""
echo "===== 3. 确认 INITIAL_ADMIN_PASSWORD 的最终来源 ====="
echo "  --- ConfigMap 原始值 ---"
kubectl get cm bk-user-api-general-envs -n "$NS" -o jsonpath='{.data.INITIAL_ADMIN_PASSWORD}' 2>/dev/null | sed 's/^/    /'
echo ""
echo "  --- bk-user-api Pod 环境变量（运行时注入值）---"
UP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-user-api' | grep Running | awk '{print $1}' | head -1)
[ -n "$UP" ] && kubectl exec "$UP" -n "$NS" -- env 2>/dev/null | grep -iE 'INITIAL_ADMIN' | sed 's/^/    /'

echo ""
echo "===== 4. bk-paas 的 adminPassword（PaaS3 自身）====="
kubectl get secret sh.helm.release.v1.bk-paas.v1 -n "$NS" -o jsonpath='{.data.release}' 2>/dev/null \
  | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null \
  | grep -oE '"(adminUsername|adminPassword)":"[^"]*"' | sort -u | sed 's/^/    /'
