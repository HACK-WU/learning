#!/usr/bin/env bash
NS=blueking

echo "=== 1. backend-api 的 3 个 ERROR 是什么 ==="
kubectl logs -n $NS deploy/bk-nodeman-backend-api --tail=120 2>/dev/null \
  | grep -iE 'error|traceback|exception' | head -8

echo ""
echo "=== 2. 这些 ERROR 是不是每次请求都报（看时间分布） ==="
kubectl logs -n $NS deploy/bk-nodeman-backend-api --tail=200 2>/dev/null \
  | grep -iE 'error' | awk '{print "    "substr($0,1,150)}' | tail -4

echo ""
echo "=== 3. 走 APIGW/ESB 正规入口调 nodeman（模拟真实调用） ==="
# 通过 apigw 转发
kubectl run cnm3 --rm -i --restart=Never --image=curlimages/curl:8.5.0 -n $NS -- \
  curl -s -w '\n  HTTP=%{http_code}\n' --max-time 15 \
  'http://bk-apigateway-api:80/api/bk-nodeman/prod/api/host/v1/?pagesize=3' 2>&1 | head -8

echo ""
echo "=== 4. nodeman 后台能否查到主机（连 DB 验证） ==="
kubectl exec -n $NS deploy/bk-nodeman-backend-api -- \
  python manage.py shell -c "from apps.node_man.models import Host; print('Host 总数:', Host.objects.count())" 2>&1 | tail -5

echo ""
echo "=== 5. nodeman 云区域（刚才同步的） ==="
kubectl exec -n $NS deploy/bk-nodeman-backend-api -- \
  python manage.py shell -c "from apps.node_man.models import Cloud; print('Cloud 区域:', list(Cloud.objects.values_list('bk_cloud_id','bk_cloud_name')))" 2>&1 | tail -5

echo ""
echo "=== 6. 清理 ==="
kubectl delete pod -n $NS cnm3 >/dev/null 2>&1
echo "  done"
