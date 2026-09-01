#!/usr/bin/env bash
# ============================================================================
# 课 11：拆除三节点集群（清理脚本）
# ============================================================================
# 只删除本课前建的容器与网络，【绝不】触碰 rabbitmq-learn（前 10 课环境）
# ============================================================================
set -euo pipefail

NET='rabbitmq-cluster'

echo "=== 拆除集群容器 ==="
for n in rmq1 rmq2 rmq3; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$n"; then
    docker rm -f "$n" >/dev/null 2>&1 || true
    echo "  已删除 $n"
  else
    echo "  $n 不存在，跳过"
  fi
done

echo ""
echo "=== 删除网络 ==="
if docker network inspect "$NET" >/dev/null 2>&1; then
  docker network rm "$NET" >/dev/null 2>&1 || true
  echo "  已删除 $NET"
else
  echo "  $NET 不存在，跳过"
fi

echo ""
echo "=== 确认既有环境完好 ==="
docker ps --filter name=rabbitmq-learn --format '{{.Names}}\t{{.Status}}'

echo ""
echo "=== 残留检查（应无 rmq1/rmq2/rmq3） ==="
docker ps -a --format '{{.Names}}' | grep -E '^rmq[123]$' || echo "  无残留 ✅"
