#!/usr/bin/env bash
# 用确认空闲的 44317/44318 重建 grafana-jaeger
set -u
NET=grafana-net
docker rm -f grafana-jaeger >/dev/null 2>&1
docker run -d --name grafana-jaeger --network $NET \
  -p 16687:16686 -p 44318:4318 -p 44317:4317 \
  -e COLLECTOR_OTLP_ENABLED=true \
  jaegertracing/jaeger:latest >/dev/null
echo "  grafana-jaeger: UI=16687  OTLP/HTTP=44318  OTLP/gRPC=44317"

for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:16687/api/services 2>/dev/null)
  [ "$c" = "200" ] && { echo "  Jaeger UI 就绪（第 $i 次）"; break; }
  sleep 2
done

echo -n "  Jaeger UI(16687)   -> "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 3 http://localhost:16687/api/services
echo -n "  OTLP HTTP(44318)   -> "; curl -s -o /tmp/o3.out -w '%{http_code}' --max-time 3 -X POST http://localhost:44318/v1/traces -H 'Content-Type: application/json' -d '{}'; echo "   body=$(head -c 40 /tmp/o3.out | tr -d '\n')"
echo ""
echo "  容器状态："
docker ps --filter "name=grafana-jaeger" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
