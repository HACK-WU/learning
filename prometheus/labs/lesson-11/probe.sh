#!/usr/bin/env bash
echo "=== 主机内存 ==="
free -g | head -2
echo ""
echo "=== 磁盘剩余 (WSL) ==="
df -h / | tail -1
echo ""
echo "=== CPU ==="
nproc
echo ""
echo "=== 当前容器 ==="
docker ps -a --format '{{.Names}}|{{.Status}}' | head -20
echo ""
echo "=== 19440+ 端口占用 ==="
for p in 19440 19451 19452 19453 19454 19455; do
  if netstat -tuln 2>/dev/null | grep -q ":$p "; then echo "$p OCCUPIED"; else echo "$p free"; fi
done
echo ""
echo "=== docker 内存限制 ==="
cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "n/a"
