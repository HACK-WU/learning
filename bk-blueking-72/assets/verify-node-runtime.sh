#!/usr/bin/env bash
# 用途：确认 kind 节点内的容器运行时与拉取工具，确保给出的命令能跑
set -uo pipefail
N=k8s-c1-calico-worker2

echo "===== 1. 节点内是否有 ctr（containerd 客户端）====="
docker exec "$N" which ctr crictl docker 2>&1

echo ""
echo "===== 2. containerd 版本 ====="
docker exec "$N" ctr version 2>&1 | head -5

echo ""
echo "===== 3. 现有 k8s.io 命名空间镜像数（确认 ctr -n k8s.io 可用）====="
docker exec "$N" ctr -n k8s.io images list 2>/dev/null | wc -l

echo ""
echo "===== 4. 该镜像当前是否已存在（未拉取则为空）====="
docker exec "$N" ctr -n k8s.io images list 2>/dev/null | grep -i 'elasticsearch' || echo "未找到 elasticsearch（确认需拉取）"

echo ""
echo "===== 5. 节点 containerd 是否能访问 registry（连通性）====="
docker exec "$N" curl -s -o /dev/null -w "HTTP %{http_code}\n" https://hub.bktencent.com/v2/ 2>&1
