#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 正确架构：ESB 与 apigateway 应共用同一对密钥 ====="
echo "  ESB 自己的密钥来源: FunctionController 表 jwt::private_public_key"
echo "  apigateway 的密钥: core_jwt 表（每 gateway 一对，bk-gse=api_id 9）"
echo ""
echo "  正常部署中，sync-builtin-gateway Job 应把 apigateway 的密钥同步给 ESB"
echo "  但本环境 ESB 用的是自己生成的那把 -> 未同步"

echo ""
echo "===== 2. 查 apigateway 侧 sync 逻辑（该把谁同步给 ESB）====="
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$DP" -n blueking -- sh -c '
  echo "  --- 找 sync esb jwt 相关命令/代码 ---"
  find /app -name "*.py" 2>/dev/null | xargs grep -ln "esb.*jwt\|jwt.*esb\|sync_esb" 2>/dev/null | head -8
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 哪个 Job 负责同步（查已完成的 sync job）====="
kubectl get job -n blueking --no-headers 2>/dev/null | grep -iE 'sync|apigw' | sed 's/^/  /'

echo ""
echo "===== 4. 关键：sync-builtin-gateway 日志里有没有写 ESB 密钥 ====="
kubectl logs -n blueking $(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'sync-builtin-gateway' | awk '{print $1}' | head -1) --tail=40 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 5. helmfile 里 ESB 的 jwt 配置 ====="
grep -rn -iE 'jwt|function.?controller' /root/bk72/install/blueking/environments/default/bkapigateway-values.yaml.gotmpl 2>/dev/null | head -10 | sed 's/^/  /'

echo ""
echo "===== 6. 修复落点确认：ESB 的 FunctionController 表 ====="
echo "  表: esb 库 FunctionController"
echo "  记录: func_code = jwt::private_public_key"
echo "  字段: wlist = {\"private_key\":..., \"public_key\":...}"
echo "  --> 修复 = 把 wlist 换成 apigateway bk-gse 那对密钥"
} > /root/fix-point.txt 2>&1
cat /root/fix-point.txt
