#!/usr/bin/env bash
set -uo pipefail
{
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. ESB 完整 403 日志（不截断，看全部字段）====="
kubectl logs "$EP" -n blueking --tail=3000 2>/dev/null | grep -iE 'add_streamto|invalid signature' | tail -3 | sed 's/^/  /'

echo ""
echo "===== 2. 关键：ESB 转发到 GSE 时，JWT 是 ESB 自己签还是透传 ====="
kubectl exec "$EP" -n blueking -- sh -c '
  echo "  --- 找 esb 里 jwt 签发逻辑 ---"
  grep -rsn "jwt\|X-Bkapi-JWT\|signature" /app/esb/components/bk/apigw/ 2>/dev/null | head -8
  echo "  --- esb 配置目录 ---"
  ls /app/esb/configs/ 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. GSE data 容器里的 jwt 校验日志（找签发方）====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl logs "$GP" -n blueking -c bk-gse-data --tail=1000 2>/dev/null | grep -iE 'jwt|verify|signature|403' | tail -15 | sed 's/^/  /'

echo ""
echo "===== 4. 换个角度：GSE 是否有多个监听端口，59702 是哪个 ====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- 监听端口 ---"
  (netstat -tlnp 2>/dev/null || ss -tlnp 2>/dev/null) | head -20
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 59702 是哪个服务（svc 对照）====="
kubectl get svc -n blueking --no-headers 2>/dev/null | grep -iE 'gse.*59702|59702' | sed 's/^/  /'
} > /root/esb-403-detail.txt 2>&1
cat /root/esb-403-detail.txt
