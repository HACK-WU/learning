#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. bk-repo-bkrepo-auth 完整配置（找数据源）====="
kubectl get cm bk-repo-bkrepo-auth -n $NS -o yaml 2>/dev/null | grep -vE '^\s*#' | head -60 | sed 's/^/  /'

echo ""
echo "===== 2. bkrepo auth 的 Secret（可能含 mongo 凭据）====="
for s in $(kubectl get secret -n $NS --no-headers 2>/dev/null | grep -iE 'mongo|bkrepo' | awk '{print $1}'); do
  echo "  --- $s ---"
  kubectl get secret $s -n $NS -o go-template='{{range $k,$v := .data}}    {{$k}} = {{$v | base64decode}}{{"\n"}}{{end}}' 2>&1 | head -6
done

echo ""
echo "===== 3. bk-repo-bkrepo-common 全量（看 mongo 连接串）====="
kubectl get cm bk-repo-bkrepo-common -n $NS -o yaml 2>/dev/null | grep -vE '^\s*#' | head -50 | sed 's/^/  /'

echo ""
echo "===== 4. mongodb 是否可达 + 有哪些库 ====="
kubectl exec netprobe -n $NS -- bash -c "
timeout 10 python3 - <<'PY'
import socket
for h in ['bk-mongodb-headless.blueking.svc.cluster.local','bk-mongodb.blueking.svc.cluster.local','bk-mongodb-headless']:
    try:
        s=socket.create_connection((h,27017),timeout=4); print('  OK',h); s.close()
    except Exception as e: print('  FAIL',h,type(e).__name__)
PY
" 2>&1

echo ""
echo "===== 5. mongodb Pod 名 ====="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -i mongo | awk '{printf "  %-46s %-14s\n", $1, $3}'
