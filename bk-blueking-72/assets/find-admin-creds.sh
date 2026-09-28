#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. helm release values 里的管理员配置 ====="
for rel in bk-user bk-paas bk-console; do
  echo "  --- $rel ---"
  kubectl get secret "sh.helm.release.v1.$rel.v1" -n "$NS" -o jsonpath='{.data.release}' 2>/dev/null \
    | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null \
    | grep -oE '"(adminUsername|adminPassword|username|password|defaultAdmin[A-Za-z]*)":"[^"]*"' \
    | sort -u | sed 's/^/      /'
done

echo ""
echo "===== 2. bk-user 相关 ConfigMap / Secret 明文项 ====="
kubectl get cm -n "$NS" 2>/dev/null | grep -iE 'user' | sed 's/^/    /'
kubectl get secret -n "$NS" 2>/dev/null | grep -iE 'user' | sed 's/^/    /'

echo ""
echo "===== 3. 数据库中实际用户表（bk-user 用 mongo/mysql）====="
# 找 mysql 实例
MP=$(kubectl get pod -n "$NS" --no-headers 2>/dev/null | grep -iE 'mysql' | grep Running | awk '{print $1}' | head -1)
echo "    mysql pod: ${MP:-无}"

echo ""
echo "===== 4. 查 login 相关 ingress（确认登录页域名）====="
kubectl get ingress -n "$NS" --no-headers 2>/dev/null | awk '{print $2}' | sort -u | sed 's/^/    /'
