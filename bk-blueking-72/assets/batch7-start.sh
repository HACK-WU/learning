#!/usr/bin/env bash
NS=blueking

G1="bk-monitor-alarm-beat bk-monitor-alarm-detect bk-monitor-alarm-trigger bk-monitor-alarm-alert bk-monitor-alarm-composite bk-monitor-alarm-nodata"
G2="bk-monitor-alarm-converge-worker bk-monitor-alarm-service-worker bk-monitor-alarm-cron-worker bk-monitor-alarm-action-worker bk-monitor-alarm-alert-worker bk-monitor-alarm-api-cron-worker"
G3="bk-monitor-alarm-access-data bk-monitor-alarm-access-event bk-monitor-alarm-access-event-worker bk-monitor-alarm-access-real-time-data bk-monitor-alarm-metadata-task-worker bk-monitor-alarm-long-task-cron-worker"
G4="bk-monitor-alarm-action-cron-worker bk-monitor-alarm-fta-action-worker bk-monitor-alarm-image-worker bk-monitor-alarm-report-cron-worker bk-monitor-alarm-webhook-action-worker bk-monitor-web-worker-resource"

n=0
for g in "$G1" "$G2" "$G3" "$G4"; do
  n=$((n+1))
  echo "=== 第 $n 波（6 个） ==="
  for d in $g; do
    kubectl scale deploy -n $NS $d --replicas=1 >/dev/null 2>&1
  done
  sleep 45
  free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
  # 盯有没有 CrashLoop
  bad=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E 'bk-monitor-(alarm|web-worker-resource)' | grep -vE 'Running|Pending|ContainerCreating' | wc -l)
  [ "$bad" -gt 0 ] && echo "    [警告] 异常 $bad 个" && \
    kubectl get pods -n $NS --no-headers | grep -E 'bk-monitor-(alarm|web-worker-resource)' | grep -vE 'Running|Pending|ContainerCreating' | head -3 | awk '{print "      "$1" "$3}'
  echo ""
done

echo "=== 等 120s 收敛 ==="
sleep 120

echo ""
echo "=== 全量状态 ==="
ok=0; bad=0
while read line; do
  st=$(echo $line | awk '{print $2}')
  nm=$(echo $line | awk '{print $1}')
  if [ "$st" = "1/1" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "  [未就绪] $nm $st"; fi
done < <(kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -E 'bk-monitor-(alarm|web-worker-resource)')
echo "  就绪 $ok / 共 $((ok+bad))"

echo ""
echo "=== 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
