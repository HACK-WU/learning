#!/usr/bin/env bash
set -uo pipefail
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== sync-apigateway.sh 内容（决定性）====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- find / -name 'sync-apigateway.sh' 2>/dev/null | head -3 | while read f; do
  echo "  === $f ==="
  kubectl exec "$GP" -n blueking -c bk-gse-data -- cat "$f" 2>&1 | sed 's/^/  /'
done

echo ""
echo "===== 备选：在 /data 下找 ====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c 'ls -la /data/ 2>&1 | head -20' | sed 's/^/  /'
} > /root/sync-sh2.txt 2>&1
cat /root/sync-sh2.txt
