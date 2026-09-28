#!/usr/bin/env bash
set -uo pipefail
echo "=== 宿主机(WSL) 多线程工具 ==="
for t in aria2c axel wget curl python3; do
  if command -v "$t" >/dev/null 2>&1; then echo "  $t: 可用"; else echo "  $t: 无"; fi
done

echo ""
echo "=== kind 节点内工具 ==="
N=k8s-c1-calico-worker2
docker exec "$N" sh -c 'for t in aria2c axel ctr crictl curl; do if command -v $t >/dev/null 2>&1; then echo "  $t: 可用"; else echo "  $t: 无"; fi; done'

echo ""
echo "=== 节点内 containerd 版本（判断是否支持 --concurrent）==="
docker exec "$N" ctr version 2>/dev/null | head -4
