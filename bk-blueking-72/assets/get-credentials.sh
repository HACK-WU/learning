#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. 全局默认管理员账号（common secret）====="
kubectl get secret -n "$NS" 2>/dev/null | grep -iE 'admin|user|account|credential|common' | sed 's/^/    /'

echo ""
echo "===== 2. 从 bk-user / 用户管理相关配置找初始账号 ====="
for s in $(kubectl get secret -n "$NS" -o name 2>/dev/null | grep -iE 'user|admin|common'); do
  n=${s#secret/}
  echo "  --- $n ---"
  kubectl get "$s" -n "$NS" -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | grep -oE '"[^"]+":' | tr -d '":' | sed 's/^/      key: /'
done

echo ""
echo "===== 3. 解码常见管理员字段 ====="
decode() { kubectl get secret "$1" -n "$NS" -o jsonpath="{.data.$2}" 2>/dev/null | base64 -d 2>/dev/null; echo; }
for s in $(kubectl get secret -n "$NS" -o name 2>/dev/null | grep -iE 'common|admin|user'); do
  n=${s#secret/}
  for k in adminUsername admin_username username ADMIN_USERNAME adminPassword admin_password password BKPAAS_ADMIN; do
    v=$(kubectl get "$s" -n "$NS" -o jsonpath="{.data.$k}" 2>/dev/null)
    if [ -n "$v" ]; then
      echo "    $n.$k = $(echo "$v" | base64 -d 2>/dev/null)"
    fi
  done
done

echo ""
echo "===== 4. 全局 values 里的管理员配置（helm release secret）====="
kubectl get secret -n "$NS" 2>/dev/null | grep 'sh.helm.release' | awk '{print $1}' | sed 's/^/    /'
