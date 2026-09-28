#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 决定性对比：GSE 各接口返回码 ====="
kubectl delete pod gsecmp -n blueking --ignore-not-found --wait=false 2>/dev/null
kubectl run gsecmp -n blueking --image=hub.bktencent.com/library/busybox:1.34.0 --restart=Never --command -- sleep 600 2>&1 | tail -1
for i in $(seq 1 30); do
  [ "$(kubectl get pod gsecmp -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && break
  sleep 2
done

kubectl exec gsecmp -n blueking -- sh -c '
probe() {
  echo -n "  $1 -> "
  wget -S -O- -m 6 "http://bk-gse-data:59702$1" 2>&1 | grep -oE "HTTP/1\.1 [0-9]{3}[^\r]*" | head -1
  echo ""
}
probe "/"
probe "/healthz"
probe "/dataroute/v1/add_streamto"
probe "/api/v1/health"
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. GSE admin（另一个组件）对照 ====="
kubectl exec gsecmp -n blueking -- sh -c '
  echo -n "  bk-gse-admin:59313 -> "
  wget -S -O- -m 6 "http://bk-gse-admin:59313/" 2>&1 | grep -oE "HTTP/1\.1 [0-9]{3}[^\r]*" | head -1
  echo ""
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 关键：ESB 日志里 GSE 的其他组件调用是否成功 ====="
EP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-bk-esb-' | grep Running | awk '{print $1}' | head -1)
echo "  --- 所有 GSE 系统调用的返回码统计 ---"
kubectl logs "$EP" -n blueking --tail=5000 2>/dev/null | grep -oE '"req_system_name": "GSE".*"req_status": [0-9]+' | grep -oE '"req_component_name": "[^"]*"|"req_status": [0-9]+' | paste - - 2>/dev/null | sort | uniq -c | sed 's/^/  /' | head -15

echo ""
echo "===== 4. nodeman 调 GSE 是否也 403（判断是全局还是仅限 monitor）====="
kubectl logs "$EP" -n blueking --tail=5000 2>/dev/null | grep -iE '"req_system_name": "GSE"' | grep -oE '"req_app_code": "[^"]*".*"req_status": [0-9]+' | sed 's/.*req_app_code": "/  app=/;s/".*req_status": /  状态=/' | sort | uniq -c | sed 's/^/  /' | head -10

kubectl delete pod gsecmp -n blueking --ignore-not-found --wait=false 2>&1 | sed 's/^/  /'
} > /root/gse-compare.txt 2>&1
cat /root/gse-compare.txt
