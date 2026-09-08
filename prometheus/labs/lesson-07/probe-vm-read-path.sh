#!/usr/bin/env bash
echo "=== VM 单节点版支持哪些 read 相关路径？ ==="
docker exec l7-vm sh -c 'wget -qO- --timeout=5 "http://localhost:8428/api/v1/query?query=up" 2>/dev/null | head -c 120'
echo
echo
echo "=== 测试 VM 的 /api/v1/read 路径 ==="
docker exec l7-prom-rr wget -qO- --timeout=5 --post-data='' \
  'http://l7-vm:8428/api/v1/read' 2>&1 | head -c 300
echo
echo
echo "=== 用另一个 Prometheus 当 remote read 后端（原生支持） ==="
echo "    目标：l7-backend（已开启 remote-write-receiver）"
docker exec l7-prom-rr wget -qO- --timeout=5 --post-data='' \
  'http://l7-backend:9090/api/v1/read' 2>&1 | head -c 300
echo
echo
echo "=== 确认 l7-backend 是否在运行 ==="
docker ps -a --format '{{.Names}}|{{.Status}}' | grep -E "l7-backend" || echo "  l7-backend 未运行"
