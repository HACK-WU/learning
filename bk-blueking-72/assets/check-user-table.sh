#!/usr/bin/env bash
set -uo pipefail
NS=blueking
MP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-mysql8' | grep Running | awk '{print $1}' | head -1)
[ -z "$MP" ] && { echo "mysql pod 未找到"; exit 1; }

echo "===== 1. bk_user_api.auth_user（Django 用户表）====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SELECT username, is_superuser, is_staff FROM bk_user_api.auth_user;" 2>/dev/null | sed 's/^/    /'

echo ""
echo "===== 2. bk_user_api 里的 profile 表（蓝鲸用户主体）====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SHOW TABLES FROM bk_user_api;" 2>/dev/null | grep -iE 'profile|tenant' | sed 's/^/    /'

echo ""
echo "===== 3. bk_login 库用户表 ====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SHOW TABLES FROM bk_login;" 2>/dev/null | head -15 | sed 's/^/    /'

echo ""
echo "===== 4. bk_paas3_apiserver 用户数（上一轮修复对象）====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SELECT COUNT(*) FROM bkpaas3_apiserver.users;" 2>/dev/null | sed 's/^/    user count: /'

echo ""
echo "===== 5. bk-user 初始化 Job 列表与状态 ====="
kubectl get jobs -n "$NS" --no-headers 2>/dev/null | grep -iE 'user' | awk '{printf "    %-52s %s\n", $1, $3}'
