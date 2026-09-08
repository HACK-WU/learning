#!/usr/bin/env bash
echo "=== VM 容器端口映射 ==="
docker port l7-vm 2>&1
echo
echo "=== VM 进程参数 ==="
docker exec l7-vm sh -c 'cat /proc/1/cmdline 2>/dev/null | tr "\0" "\n"' 2>&1 | head -n 10
echo
echo "=== VM 日志 ==="
docker logs --tail 15 l7-vm 2>&1
echo
echo "=== 从宿主机访问映射端口 19101 ==="
docker exec l7-prom-rr wget -qO- --timeout=5 'http://l7-vm:8428/health' 2>&1 | head -c 200
echo
echo "=== 尝试 8428 以外的端口 ==="
for p in 8428 8429 8480 8481; do
  echo -n "  port $p: "
  docker exec l7-prom-rr wget -qO- --timeout=3 "http://l7-vm:$p/health" 2>&1 | head -c 60
  echo
done
