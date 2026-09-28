#!/usr/bin/env bash
NS=blueking

echo "=== STEP 1: 裁前留证 —— nodeman 组件 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep nodeman | awk '{printf "    %-46s %s\n",$1,$2}'

echo ""
echo "=== STEP 2: 裁前留证 —— celery 任务链证据 ==="
echo "  [beat] 调度:"
kubectl logs -n $NS deploy/bk-nodeman-backend-celery-beat --tail=40 2>/dev/null \
  | grep 'Sending due task' | tail -1 | sed 's/^/      /' | cut -c1-160
echo "  [worker] 执行:"
kubectl logs -n $NS deploy/bk-nodeman-backend-common-worker --tail=40 2>/dev/null \
  | grep 'succeeded in' | tail -1 | sed 's/^/      /' | cut -c1-160

echo ""
echo "=== STEP 3: 裁前留证 —— DB 级证据 ==="
kubectl exec -n $NS deploy/bk-nodeman-backend-api -- \
  python manage.py shell -c "from apps.node_man.models import Cloud; print('  Cloud:', list(Cloud.objects.values_list('bk_cloud_id','bk_cloud_name')))" 2>/dev/null | grep Cloud

echo ""
echo "=== STEP 4: 裁前内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 5: 裁掉本批新起的 7 个（保留原本就在跑的 api/saas-api/saas-web） ==="
for d in bk-nodeman-backend-celery-beat bk-nodeman-backend-common-pworker \
         bk-nodeman-backend-common-worker bk-nodeman-backend-sync-host \
         bk-nodeman-backend-sync-host-re bk-nodeman-backend-sync-process \
         bk-nodeman-backend-sync-watch; do
  kubectl scale deploy -n $NS $d --replicas=0 >/dev/null 2>&1
done
echo "  已 scale 0: 7 个"

echo ""
echo "=== STEP 6: 等 90s ==="
sleep 90
free -g | sed -n '2p' | awk '{printf "    裁后 used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== STEP 7: 集群健康 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -4

echo ""
echo "=== STEP 8: 核心页面复查 ==="
for d in paas.example.com bkpaas.paas.example.com bknodeman.paas.example.com bkiam.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "    %-32s %s\n" "$d" "$code"
done

echo ""
echo "=== STEP 9: 剩余未验证 ==="
echo "  deploy 0/0: $(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
