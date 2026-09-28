#!/usr/bin/env bash
NS=blueking

echo "=== 1. nodeman API 真实调用（ESB 接口） ==="
kubectl run cnm1 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -w '\n  HTTP=%{http_code}\n' --max-time 15 \
  'http://bk-nodeman-backend-api/api/host/v1/?pagesize=5' 2>&1 | head -10

echo ""
echo "=== 2. nodeman saas-api ==="
kubectl run cnm2 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -o /dev/null -w "    saas-api -> HTTP %{http_code}\n" --max-time 12 \
  'http://bk-nodeman-saas-api:10300/' 2>&1 | grep HTTP

echo ""
echo "=== 3. 页面入口 ==="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 'http://bknodeman.paas.example.com/' 2>/dev/null)
echo "    bknodeman.paas.example.com -> $code"

echo ""
echo "=== 4. celery worker 是否真的在消费（看日志） ==="
kubectl logs -n $NS deploy/bk-nodeman-backend-common-worker --tail=25 2>/dev/null | tail -8

echo ""
echo "=== 5. celery-beat 是否在调度任务 ==="
kubectl logs -n $NS deploy/bk-nodeman-backend-celery-beat --tail=20 2>/dev/null | tail -6

echo ""
echo "=== 6. sync-host 日志（同步主机） ==="
kubectl logs -n $NS deploy/bk-nodeman-backend-sync-host --tail=20 2>/dev/null | tail -6

echo ""
echo "=== 7: GSE 通道健康（nodeman 靠 GSE 管控主机） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bk-gse' | awk '{printf "    %-44s %s\n",$1,$3}'

echo ""
echo "=== 8: 日志 ERROR 检查 ==="
for d in bk-nodeman-backend-api bk-nodeman-backend-common-worker bk-nodeman-backend-sync-watch; do
  n=$(kubectl logs -n $NS deploy/$d --tail=50 2>/dev/null | grep -ciE 'error|traceback' )
  printf "    %-44s ERROR=%s\n" "$d" "$n"
done

echo ""
echo "=== 9: 清理 ==="
kubectl delete pod -n $NS cnm1 cnm2 >/dev/null 2>&1
echo "  done"
