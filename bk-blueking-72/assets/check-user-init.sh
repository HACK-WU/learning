#!/usr/bin/env bash
set -uo pipefail
NS=blueking
MP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-mysql8' | grep Running | awk '{print $1}' | head -1)
[ -z "$MP" ] && { echo "mysql pod 未找到"; exit 1; }

echo "===== 1. 各用户表行数（判断是否真的空）====="
for q in "bk_user_api.auth_user" "bk_user_api.profiles_profile" "bk_login.login_bktoken" "bk_user_saas.auth_user"; do
  db=${q%%.*}; tb=${q##*.}
  c=$(kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e "SELECT COUNT(*) FROM \`$db\`.\`$tb\`;" 2>/dev/null)
  printf "    %-34s = %s\n" "$q" "${c:-查询失败}"
done

echo ""
echo "===== 2. bk-user-api Pod 日志：初始化是否执行 ====="
UP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-user-api' | grep Running | awk '{print $1}' | head -1)
[ -n "$UP" ] && kubectl logs "$UP" -n "$NS" --tail=40 2>/dev/null | grep -iE 'admin|init|creat|superuser|error|fail' | head -15 | sed 's/^/    /'

echo ""
echo "===== 3. 是否存在 initial 相关 Job/Pod ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'user' | awk '{printf "    %-50s %s\n", $1, $3}'

echo ""
echo "===== 4. bk-user-api Deployment 就绪 ====="
kubectl get deploy -n "$NS" --no-headers 2>/dev/null | grep -iE 'user|login|console' | awk '{printf "    %-40s %s\n", $1, $2}'
