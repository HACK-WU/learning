#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 找 sync-apigateway.sh 脚本本体 ====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c 'which sync-apigateway.sh 2>&1; find / -name "sync-apigateway.sh" -maxdepth 5 2>/dev/null | head -3' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 该 Job 的 pod 还在吗（看日志）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-gse-apigw-sync' | sed 's/^/  /'

echo ""
echo "  --- 若 pod 还在，看它做了什么 ---"
JP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-gse-apigw-sync' | awk '{print $1}' | head -1)
if [ -n "$JP" ]; then
  kubectl logs "$JP" -n blueking --tail=40 2>&1 | sed 's/^/  /'
fi

echo ""
echo "===== 3. 从镜像里找脚本内容（决定性）====="
GP2=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
for c in bk-gse-data bk-gse-data-init; do
  echo "  --- container: $c ---"
  kubectl exec "$GP2" -n blueking -c "$c" -- sh -c 'ls /usr/local/bin/ /bin/ /data/ 2>/dev/null | grep -i sync | head -5' 2>&1 | sed 's/^/    /'
done

echo ""
echo "===== 4. 关键推演：证书从哪来 ====="
echo "  ConfigMap bk-gse-certs 由 helm chart bk-gse-ce 渲染"
echo "  chart 内 gseCert 段只含 gse 自身 TLS 证书，未见 apigw_jwt.crt 来源"
echo "  -> apigw_jwt.crt 极可能由 bk-gse-apigw-sync Job 运行时查询 apigateway 后写入"
echo "  -> 即：该 Job 从 apigateway 拿 bk-gse gateway 的公钥，写进 ConfigMap"
} > /root/sync-sh.txt 2>&1
cat /root/sync-sh.txt
