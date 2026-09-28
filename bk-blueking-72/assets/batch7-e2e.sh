#!/usr/bin/env bash
NS=blueking

echo "=== 1. beat 是否在调度告警任务 ==="
kubectl logs -n $NS deploy/bk-monitor-alarm-beat --tail=30 2>/dev/null | tail -5 | cut -c1-190

echo ""
echo "=== 2. detect（检测）日志 ==="
kubectl logs -n $NS deploy/bk-monitor-alarm-detect --tail=30 2>/dev/null | tail -4 | cut -c1-190

echo ""
echo "=== 3. trigger（触发）日志 ==="
kubectl logs -n $NS deploy/bk-monitor-alarm-trigger --tail=30 2>/dev/null | tail -4 | cut -c1-190

echo ""
echo "=== 4. converge-worker（收敛）==="
kubectl logs -n $NS deploy/bk-monitor-alarm-converge-worker --tail=20 2>/dev/null | tail -3 | cut -c1-190

echo ""
echo "=== 5. alert（告警生成）==="
kubectl logs -n $NS deploy/bk-monitor-alarm-alert --tail=20 2>/dev/null | tail -3 | cut -c1-190

echo ""
echo "=== 6. nodata（无数据告警）==="
kubectl logs -n $NS deploy/bk-monitor-alarm-nodata --tail=20 2>/dev/null | tail -3 | cut -c1-190

echo ""
echo "=== 7. composite（关联告警）==="
kubectl logs -n $NS deploy/bk-monitor-alarm-composite --tail=20 2>/dev/null | tail -3 | cut -c1-190

echo ""
echo "=== 8. ERROR 扫描（24 个） ==="
for d in $(kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -E 'bk-monitor-(alarm|web-worker-resource)' | awk '{print $1}'); do
  n=$(kubectl logs -n $NS deploy/$d --tail=60 2>/dev/null | grep -ciE 'error|traceback')
  [ "$n" != "0" ] && printf "    %-38s ERROR=%s\n" "$d" "$n"
done
echo "  (只列非0)"
