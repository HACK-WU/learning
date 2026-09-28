#!/usr/bin/env bash
NS=blueking

# 关键修正：用 -l 标签选择器精确定位，不用 deploy/xxx（会匹配错 pod）
log() {
  app=$1; shift
  pod=$(kubectl get pod -n $NS -l "app.kubernetes.io/name=$app" --no-headers 2>/dev/null | head -1 | awk '{print $1}')
  [ -z "$pod" ] && pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep "^$app-" | head -1 | awk '{print $1}')
  if [ -z "$pod" ]; then echo "    [找不到 pod] $app"; return; fi
  echo "    pod=$pod"
  kubectl logs -n $NS $pod --tail=25 2>&1 | tail -5 | sed 's/^/      /' | cut -c1-195
}

echo "=== 1. beat（调度器）==="
log bk-monitor-alarm-beat

echo ""
echo "=== 2. detect（检测）==="
log bk-monitor-alarm-detect

echo ""
echo "=== 3. trigger（触发）==="
log bk-monitor-alarm-trigger

echo ""
echo "=== 4. alert（告警生成）==="
log bk-monitor-alarm-alert

echo ""
echo "=== 5. nodata（无数据告警）==="
log bk-monitor-alarm-nodata

echo ""
echo "=== 6. composite（关联告警）==="
log bk-monitor-alarm-composite

echo ""
echo "=== 7. converge-worker（收敛）==="
log bk-monitor-alarm-converge-worker

echo ""
echo "=== 8. action-worker（动作执行）==="
log bk-monitor-alarm-action-worker
