#!/usr/bin/env bash
# 用途：后台持续观察部署状态（供文档记录最终结论）
set -uo pipefail
NS=blueking

for i in $(seq 1 20); do
  echo "===== 第 $i 次检查 $(date '+%H:%M:%S') ====="
  ready=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c '1/1')
  total=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l)
  echo "就绪: $ready / $total"
  kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $1, $2, $3}' | head -15
  if [ "$ready" -eq "$total" ] && [ "$total" -gt 0 ]; then
    echo "✅ 全部就绪"
    break
  fi
  sleep 60
done
