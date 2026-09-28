#!/usr/bin/env bash
set -uo pipefail
NS=blueking
MP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-mysql8' | grep Running | awk '{print $1}' | head -1)
[ -z "$MP" ] && { echo "mysql pod 未找到"; exit 1; }

echo "===== 1. profiles_profile 里那 1 行是谁 ====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SELECT id, username, display_name, enabled FROM bk_user_api.profiles_profile;" 2>/dev/null | sed 's/^/    /'

echo ""
echo "===== 2. 表结构（确认 username 字段名）====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "DESC bk_user_api.profiles_profile;" 2>/dev/null | awk '{print "    "$1}' | head -20

echo ""
echo "===== 3. bk_login 的 login_bktoken（是否有登录会话）====="
kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
  "SELECT COUNT(*) FROM bk_login.login_bktoken;" 2>/dev/null | sed 's/^/    token数: /'

echo ""
echo "===== 4. bk_user_api 是否有 initial_data / init Job 历史 ====="
kubectl get jobs -n "$NS" --no-headers 2>/dev/null | awk '{print $1}' | grep -iE 'initial|init' | sed 's/^/    /'

echo ""
echo "===== 5. 全集群 initial 类 Job（paas3 有，bk-user 有无？）====="
kubectl get jobs -n "$NS" --no-headers 2>/dev/null | grep -iE 'initial|init-data|create-admin' | awk '{printf "    %-52s %s\n", $1, $3}'
