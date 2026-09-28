#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 固定现场：migrate-db Job 定义 ====="
kubectl get job bkpaas3-apiserver-migrate-db-1 -n $NS -o yaml > /tmp/paas3-migrate-job.yaml 2>/dev/null \
  && echo "  已保存 $(wc -l < /tmp/paas3-migrate-job.yaml) 行" || echo "  保存失败"

echo ""
echo "===== 2. bkrepo gateway 是否真能访问（init_bkrepo 的调用目标）====="
kubectl get svc -n $NS --no-headers 2>/dev/null | grep -E 'bkrepo-gateway|bkrepo-auth' | awk '{printf "  %-36s %-12s %s\n", $1, $2, $5}'

echo ""
echo "===== 3. 实测：从 paas3 网络访问 bkrepo gateway ====="
kubectl run bkrepo-probe --rm -i --restart=Never -n $NS \
  --image=hub.bktencent.com/library/busybox:1.34.0 --timeout=60s -- \
  wget -q -O- --timeout=10 http://bk-repo-bkrepo-gateway.$NS.svc.cluster.local:80/ 2>&1 | head -5 | sed 's/^/    /' \
  || echo "    探测失败或超时"

echo ""
echo "===== 4. bkrepo gateway 日志（看有没有 401/403）====="
kubectl logs -n $NS deploy/bk-repo-bkrepo-gateway 2>&1 | tail -10 | sed 's/^/    /'

echo ""
echo "===== 5. bkrepo auth 日志 ====="
kubectl logs -n $NS deploy/bk-repo-bkrepo-auth 2>&1 | tail -8 | sed 's/^/    /'

echo ""
echo "===== 6. paas3 的 bkrepo 凭据 Secret 是否存在 ====="
kubectl get secret -n $NS --no-headers 2>/dev/null | grep -E 'bkrepo' | awk '{printf "  %-46s %s\n", $1, $2}'
