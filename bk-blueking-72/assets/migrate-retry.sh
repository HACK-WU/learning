#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
cd "$BK" || exit 1
export HELMFILE=/root/bk72/install/bin/helmfile

{
echo "===== 1. 删除已失败的 Job（backoffLimit 耗尽，不会自愈）====="
kubectl delete job bk-monitor-migrate-1 -n blueking --ignore-not-found 2>&1 | sed 's/^/  /'
sleep 3
kubectl get job -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | sed 's/^/  /' || echo "  (migrate Job 已删除)"

echo ""
echo "===== 2. 重跑 helmfile sync 重建（04-bkmonitor）====="
echo "开始: $(date '+%F %T')"
timeout 2400 $HELMFILE -f 04-bkmonitor.yaml.gotmpl sync 2>&1 | tail -40
echo "结束: $(date '+%F %T')"

echo ""
echo "===== 3. migrate Job 是否重建 ====="
kubectl get job -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | sed 's/^/  /' || echo "  (无 migrate Job)"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate' | sed 's/^/  /' || echo "  (无 migrate Pod)"
} > /root/migrate-retry.txt 2>&1
cat /root/migrate-retry.txt
