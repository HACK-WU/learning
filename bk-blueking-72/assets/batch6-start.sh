#!/usr/bin/env bash
NS=blueking

echo "=== STEP 1: 起 3 个核心 worker（beat / common-worker / common-pworker） ==="
kubectl scale deploy -n $NS bk-nodeman-backend-celery-beat --replicas=1 >/dev/null 2>&1 && echo "  [起] celery-beat"
sleep 25
kubectl scale deploy -n $NS bk-nodeman-backend-common-worker --replicas=1 >/dev/null 2>&1 && echo "  [起] common-worker"
sleep 25
kubectl scale deploy -n $NS bk-nodeman-backend-common-pworker --replicas=1 >/dev/null 2>&1 && echo "  [起] common-pworker"
sleep 60

echo ""
echo "=== STEP 2: 状态 ==="
for d in bk-nodeman-backend-celery-beat bk-nodeman-backend-common-worker bk-nodeman-backend-common-pworker; do
  kubectl get deploy -n $NS $d --no-headers 2>/dev/null | awk '{printf "  %-44s %s\n",$1,$2}'
done

echo ""
echo "=== STEP 3: 起 4 个 sync（无资源限制，逐个起并盯内存） ==="
for d in bk-nodeman-backend-sync-host bk-nodeman-backend-sync-host-re bk-nodeman-backend-sync-process bk-nodeman-backend-sync-watch; do
  kubectl scale deploy -n $NS $d --replicas=1 >/dev/null 2>&1 && echo "  [起] $d"
  sleep 30
  free -g | sed -n '2p' | awk '{printf "         used=%sG avail=%sG\n",$3,$7}'
done

echo ""
echo "=== STEP 4: 等 90s ==="
sleep 90

echo ""
echo "=== STEP 5: nodeman 全量状态 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep nodeman | awk '{printf "  %-46s %s\n",$1,$2}'

echo ""
echo "=== STEP 6: 未就绪的 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep nodeman | awk '$3!="Running"{print "  [未就绪] "$1" "$3}'
echo "  (空=全好)"

echo ""
echo "=== STEP 7: 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
