#!/usr/bin/env bash
# 课 9 环境：Loki(3101) + Jaeger(16687) + 造日志的 loggen 容器
# 设计原则：不污染既有环境 ——
#   - Loki 全新实例 grafana-loki，端口 3101
#   - Jaeger 另建 grafana-jaeger，端口 16687（复用 jaeger 镜像，但不碰 OTel 课程的 jaeger-lab03:16686）
#   - 日志源用 python 生成，可控且带结构化标签，便于讲 LogQL 标签模型
set -u
NET=grafana-net

echo "=== 0. 网络 ==="
docker network create $NET 2>/dev/null || echo "  $NET 已存在"

echo "=== 1. Loki（3101）==="
docker rm -f grafana-loki >/dev/null 2>&1
docker run -d --name grafana-loki --network $NET -p 3101:3100 \
  grafana/loki:3.5.6 -config.file=/etc/loki/local-config.yaml >/dev/null
echo "  grafana-loki -> 宿主 3101"

echo "=== 2. Jaeger（16687）==="
docker rm -f grafana-jaeger >/dev/null 2>&1
docker run -d --name grafana-jaeger --network $NET -p 16687:16686 \
  -e COLLECTOR_OTLP_ENABLED=true \
  jaegertracing/jaeger:latest >/dev/null
echo "  grafana-jaeger -> 宿主 16687"

echo "=== 3. 等就绪 ==="
loki_ready() { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:3101/ready 2>/dev/null)" = "200" ]; }
jaeger_ready() { curl -s --max-time 3 http://localhost:16687/api/services 2>/dev/null | grep -q '"data"'; }

for i in $(seq 1 45); do
  if loki_ready && jaeger_ready; then
    echo "  第 ${i} 次探测（约 $((i*2)) 秒）：Loki + Jaeger 均就绪"
    break
  fi
  sleep 2
done

echo -n "  Loki   /ready        -> "; loki_ready && echo "200 ✅" || echo "未就绪 ❌"
echo -n "  Jaeger /api/services -> "; jaeger_ready && echo "200 ✅" || echo "未就绪 ❌"

echo ""
echo "=== 4. 最终状态 ==="
docker ps --filter "name=grafana-" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
