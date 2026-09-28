#!/usr/bin/env bash
set -uo pipefail
{
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. GSE data 完整日志（不限 grep，看它自己说啥）====="
kubectl logs "$GP" -n blueking -c bk-gse-data --tail=80 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. GSE data 的 init 容器日志（init 是否真的成功）====="
kubectl logs "$GP" -n blueking -c bk-gse-data-init --tail=40 2>&1 | sed 's/^/  /'
echo "  --- check-zookeeper init ---"
kubectl logs "$GP" -n blueking -c bk-gse-data-check-zookeeper --tail=30 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. GSE 配置文件里的鉴权段（是否强制要求 JWT）====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- gse_data.conf 全文关键段 ---"
  cat /data/gse/etc/gse_data.conf 2>/dev/null | head -50
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. GSE 是否连上了它需要的后端 ====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- 已建立连接 ---"
  (netstat -tnp 2>/dev/null || ss -tnp 2>/dev/null) | grep -iE "gse_data|ESTABLISHED" | head -12
' 2>&1 | sed 's/^/  /'
} > /root/gse-final.txt 2>&1
cat /root/gse-final.txt
