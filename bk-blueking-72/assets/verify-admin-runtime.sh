#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. 运行时 ConfigMap 里的实际账号（非 chart 默认值）====="
echo "  --- bk-user-api-general-envs ---"
kubectl get cm bk-user-api-general-envs -n "$NS" -o jsonpath='{.data}' 2>/dev/null \
  | tr ',' '\n' | grep -iE 'username|password|admin|init' | sed 's/^/    /'

echo ""
echo "  --- bk-user-saas-general-envs ---"
kubectl get cm bk-user-saas-general-envs -n "$NS" -o jsonpath='{.data}' 2>/dev/null \
  | tr ',' '\n' | grep -iE 'username|password|admin|init' | sed 's/^/    /'

echo ""
echo "===== 2. 初始化 Job 日志（看实际创建了什么账号）====="
for j in $(kubectl get jobs -n "$NS" --no-headers 2>/dev/null | grep -iE 'user.*init|init.*user' | awk '{print $1}'); do
  echo "  --- job: $j ---"
  kubectl logs "job/$j" -n "$NS" --tail=25 2>/dev/null | grep -iE 'admin|user|password|created|初始化|创建' | head -12 | sed 's/^/    /'
done

echo ""
echo "===== 3. 查 bk-user 数据库中真实用户 ====="
MP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -E '^bk-mysql8' | grep Running | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  echo "    使用 pod: $MP"
  kubectl exec "$MP" -n "$NS" -- mysql -uroot -pblueking -N -e \
    "SHOW DATABASES;" 2>/dev/null | grep -iE 'user|auth|bk' | sed 's/^/    db: /'
fi

echo ""
echo "===== 4. 蓝鲸 console/登录页相关 Pod ====="
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -iE 'console|login|usermgr' | awk '{printf "    %-46s %s\n", $1, $3}'
