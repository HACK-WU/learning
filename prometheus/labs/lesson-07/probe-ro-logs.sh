#!/usr/bin/env bash
echo "=== l7-prom-ro 启动日志（remote read 部分） ==="
docker logs l7-prom-ro 2>&1 | grep -iE "remote|read|error" | head -n 20
echo
echo "=== l7-prom-ro 完整日志尾部 ==="
docker logs --tail 12 l7-prom-ro 2>&1
echo
echo "=== l7-prom-rr 日志（对照） ==="
docker logs l7-prom-rr 2>&1 | grep -iE "remote read|Starting|Replaying" | head -n 10
echo
echo "=== 从 ro 容器内能否连到 VM ==="
docker exec l7-prom-ro wget -qO- --timeout=5 'http://l7-vm:8428/health' 2>&1
echo
echo "=== ro 的 remote_read 配置是否加载 ==="
docker exec l7-prom-ro wget -qO- 'http://localhost:9090/api/v1/status/config' 2>/dev/null \
  | tr ',' '\n' | grep -iE "read_recent|remote|l7-vm" | head -n 10
