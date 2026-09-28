#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 方案 A 验证：重建 migrate Job，看 403 是否消失 ====="
echo ""

echo "--- 1. 找 migrate job ---"
kubectl get job -n blueking --no-headers 2>/dev/null | grep -iE 'monitor.*migrate|migrate' | head -5 | sed 's/^/  /'

echo ""
echo "--- 2. 找监控的 migrate（04-bkmonitor 相关）---"
kubectl get job -n blueking --no-headers 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "--- 3. 删掉旧 job 让 helm/init 重建，或找其 owner ---"
for j in $(kubectl get job -n blueking --no-headers 2>/dev/null | awk '{print $1}'); do
  # 跳过 apigw sync 和 gse sync
  case "$j" in
    *apigw*|*gse*) continue;;
  esac
  echo "  job=$j  completions=$(kubectl get job $j -n blueking -o jsonpath='{.status.succeeded}/{.spec.completions}' 2>/dev/null)"
  kubectl get job "$j" -n blueking -o jsonpath='  labels={.metadata.labels}{"\n"}' 2>/dev/null | sed 's/^/  /'
done
} > /root/find-migrate.txt 2>&1
cat /root/find-migrate.txt
