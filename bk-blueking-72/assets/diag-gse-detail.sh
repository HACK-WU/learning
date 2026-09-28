#!/usr/bin/env bash
set -uo pipefail

echo "===== 1. GSE 相关 service（确认接口地址）====="
kubectl get svc -n blueking --no-headers 2>/dev/null | grep -iE 'gse' | head -15 | sed 's/^/  /'

echo ""
echo "===== 2. 监控里 GSE API 的实际 host 配置 ====="
kubectl get cm bk-monitor-monitor-env -n blueking -o yaml 2>/dev/null | grep -iE 'gse|BK_API|api' | head -20 | sed 's/^/  /'

echo ""
echo "===== 3. GSE 自身日志（看它为什么返 403）====="
kubectl logs -n blueking deploy/bk-gse-admin --tail=30 2>/dev/null | sed 's/^/  /'
echo "  --- bk-gse-config ---"
kubectl logs -n blueking deploy/bk-gse-proc --tail=20 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 4. GSE 的 403 常见原因：ESB/apigw 是否注册 bk-gse ====="
kubectl exec -n blueking deploy/bk-apigateway-core-api -- ls / 2>/dev/null | head -5 | sed 's/^/  /'
echo "  --- 查 esb 里 gse 配置 ---"
kubectl get cm -n blueking -o name 2>/dev/null | grep -iE 'esb' | head -10 | sed 's/^/  /'

echo ""
echo "===== 5. 对比：其他已装组件（如 cmdb）怎么调 gse ====="
kubectl get deploy bk-cmdb-apiserver -n blueking -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null | grep -iE 'GSE' | head -10 | sed 's/^/  /'

echo ""
echo "===== 6. 直接 curl GSE config 接口（绕过网关看是否通）====="
kubectl run curlgse --rm -i --restart=Never --image=curlimages/curl:latest -n blueking -- \
  curl -s -m 10 -o /dev/null -w "gse-config http=%{http_code}\n" http://bk-gse-config:59702/ 2>&1 | tail -3 | sed 's/^/  /'
