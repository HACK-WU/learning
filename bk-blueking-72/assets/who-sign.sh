#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 关键问题：到底谁签 JWT？ESB 还是 apigateway？ ====="
echo ""
echo "  两个可能："
echo "  (a) monitor -> apigateway -> GSE   : apigateway 用自己的 bk-gse 密钥签 -> GSE 验(同钥) 应通过"
echo "  (b) monitor -> ESB -> GSE          : ESB 用自己密钥签 -> GSE 验(bk-gse钥) 失败"
echo ""
echo "  需要确认 monitor 调 GSE 的实际路径"

echo ""
echo "===== 1. GSE 收到请求的 host/来源（从 ESB 日志看调用方）====="
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$EP" -n blueking -c bk-esb -- sh -c '
find /app -name "*.log" -o -name "esb*.log" 2>/dev/null | head -5
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. builtinGateway 里 bk-gse 的 publicKeyBase64 源头 ====="
echo "  --- 搜 builtinGateway 定义 ---"
grep -rn 'builtinGateway' /root/bk72/install/blueking/ 2>/dev/null | grep -v '\.bak' | grep -v 'values.yaml.gotmpl' | head -8 | sed 's/^/  /'

echo ""
echo "===== 3. 决定性：apigateway 转发 GSE 时，用哪把钥签 ====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
find /app -name "*.py" 2>/dev/null | xargs grep -ln "X-Bkapi-JWT\|bkapi_jwt\|jwt.encode" 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. apigateway 每个 gateway 用自己的密钥签（正常设计）====="
echo "  若如此：apigateway 用 bk-gse 密钥签 -> GSE 用同钥验 -> 应通过"
echo "  那 403 的签名方就不是 apigateway，而是 ESB"
echo "  -> 需确认 monitor 到底走 ESB 还是 apigateway"

echo ""
echo "===== 5. monitor 调 GSE 的配置（走哪个入口）====="
kubectl get cm -n blueking --no-headers 2>/dev/null | grep -i monitor | head -8 | sed 's/^/  /'
} > /root/who-sign.txt 2>&1
cat /root/who-sign.txt
