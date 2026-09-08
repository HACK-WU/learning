#!/usr/bin/env bash
set -u
L7="$(pwd)/labs/lesson-07"

echo "=== 校验 agent 配置（注意：不能含 rule_files） ==="
docker run --rm -v "$L7/agent.yml:/tmp/c.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/c.yml 2>&1 | tail -n 3

echo
echo "=== 启动 Agent 模式实例 ==="
docker rm -f l7-agent >/dev/null 2>&1 || true
mkdir -p "$L7/data-agent"
chmod 777 "$L7/data-agent" 2>/dev/null || true
docker run -d --name l7-agent --network l7net -p 19107:9090 \
  -v "$L7/agent.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$L7/data-agent:/data-agent" \
  prom/prometheus:v3.14.0 \
  --agent \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.agent.path=/data-agent \
  --web.enable-lifecycle >/dev/null
echo "l7-agent up (http://localhost:19107)"

sleep 20

echo
echo "=== Agent 启动日志（看它声明了什么、禁用了什么） ==="
docker logs l7-agent 2>&1 | grep -iE "agent|mode|disabled|WAL|server is ready" | head -n 15

echo
echo "=== Agent 容器状态 ==="
docker inspect -f '{{.State.Status}}' l7-agent 2>/dev/null
