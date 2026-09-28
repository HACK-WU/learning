#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
cd "$BK" || exit 1
export HELMFILE=/root/bk72/install/bin/helmfile

echo "===== 安装 monitor-storage (kafka/consul/influxdb) ====="
echo "开始: $(date '+%F %T')"

timeout 2400 $HELMFILE -f monitor-storage.yaml.gotmpl sync 2>&1 | tail -60

echo ""
echo "结束: $(date '+%F %T')"
echo "exit=$?"

echo ""
echo "===== 结果检查 ====="
for r in bk-kafka bk-consul bk-influxdb; do
  echo "--- $r ---"
  helm status "$r" -n blueking --short 2>/dev/null | head -3 | sed 's/^/  /'
  kubectl get pods -n blueking -l "app.kubernetes.io/instance=$r" --no-headers 2>/dev/null | head -8 | sed 's/^/  /'
done
