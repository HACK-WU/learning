#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 监控调 GSE 走的是哪个 URL（从 values 查）====="
grep -iE 'gse|bkapi|apigw' /root/bk72/install/blueking/environments/default/bkmonitor-values.yaml.gotmpl 2>/dev/null | grep -iE 'url|addr|host|api' | head -15 | sed 's/^/  /'

echo ""
echo "===== 2. GSE 在 apigateway 的注册状态 ====="
kubectl exec -n blueking deploy/bk-apigateway-dashboard -- sh -c 'echo skip' 2>/dev/null
echo "  --- 查 apigw 里 gse 相关资源 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'apigateway' | sed 's/^/  /' | head -8

echo ""
echo "===== 3. 用监控 Pod 内的配置直接复现 403（关键取证）====="
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor-migrate-2' | awk '{print $1}' | head -1)
echo "  POD=$MPOD"
echo "  --- 容器内 GSE 相关环境变量 ---"
kubectl exec "$MPOD" -n blueking -c on-migrate -- env 2>/dev/null | grep -iE 'gse|bkapi|apigw|app_code|app_secret' | sed 's/^/    /' | head -20

echo ""
echo "===== 4. 容器内直接 curl GSE 组件接口（不带认证，看返回）====="
kubectl exec "$MPOD" -n blueking -c on-migrate -- sh -c '
for u in http://bkapi.paas.example.com/api/bk-gse/prod/ http://bk-api-gateway.blueking.svc.cluster.local/api/bk-gse/prod/; do
  echo "  URL=$u"
  curl -s -m 8 -o /dev/null -w "    HTTP=%{http_code}\n" "$u" 2>&1
done' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. GSE 服务自身接口是否 403（直连 gse）====="
kubectl exec "$MPOD" -n blueking -c on-migrate -- sh -c '
for u in http://bk-gse-admin:59629/ http://bk-gse-cluster:59313/ http://bk-gse-data:58625/; do
  echo "  URL=$u"
  curl -s -m 8 -o /dev/null -w "    HTTP=%{http_code}\n" "$u" 2>&1
done' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 6. app_secret 里 gse 与 monitor 的配对 ====="
grep -iE 'gse|monitor' /root/bk72/install/blueking/environments/default/app_secret.yaml 2>/dev/null | sed 's/^/  /'
} > /root/gse-403-deep.txt 2>&1
cat /root/gse-403-deep.txt
