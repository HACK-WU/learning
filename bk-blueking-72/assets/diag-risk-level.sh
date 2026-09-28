#!/usr/bin/env bash
set -uo pipefail
NS=ingress-nginx
CM=ingress-nginx-controller

echo "===== 1. controller 是否已重载（看 configmap 是否被读到）====="
kubectl get cm $CM -n $NS -o yaml 2>/dev/null | sed -n '/^data:/,$p' | sed 's/^/  /'

echo ""
echo "===== 2. controller 启动参数（找 annotation-risk-level / enable-annotation-validation）====="
kubectl get deploy ingress-nginx-controller -n $NS -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | tr ',' '\n' | sed 's/^/  /'

echo ""
echo "===== 3. 关键：annotation-risk-level 是否存在（"risky" 字眼的来源）====="
echo "  搜索 controller 日志中的 risk 相关"
kubectl logs -n $NS -l app.kubernetes.io/name=ingress-nginx --tail=100 2>/dev/null | grep -iE 'risk|annotation-validation|snippet' | tail -10 | sed 's/^/    /'

echo ""
echo "===== 4. 清理测试 ingress ====="
kubectl delete ingress snippet-probe -n default 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 验证：annotation-risk-level 应为 Critical 才放行 snippet ====="
echo "  当前需设置: controller.config.annotations-risk-level: Critical"
echo "  或启动参数: --annotations-risk-level=Critical"
