#!/bin/bash
echo "=== 1. 当前所有容器状态 ==="
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | sort
echo

echo "=== 2. 现有 docker 网络 ==="
docker network ls --format '{{.Name}}\t{{.Driver}}'
echo

echo "=== 3. 各 Grafana 实例健康 ==="
for P in 3001 3002 3003 3004 3005 3006 3007 3008; do
  R=$(curl -s --noproxy '*' -m 4 http://localhost:$P/api/health | tr -d '\n' | head -c 90)
  if [ -n "$R" ]; then echo "  $P: $R"; else echo "  $P: (无响应)"; fi
done
echo

echo "=== 4. 各实例的 provisioning 目录 ==="
for C in grafana-lab grafana-prov; do
  echo "  --- $C ---"
  docker exec $C ls /etc/grafana/provisioning/ 2>&1 | head -8
  docker exec $C ls /etc/grafana/provisioning/datasources/ 2>&1 | head -5
  docker exec $C ls /etc/grafana/provisioning/dashboards/ 2>&1 | head -5
done
echo

echo "=== 5. Loki / Jaeger / Prometheus 可达性 ==="
curl -s --noproxy '*' -m 5 http://localhost:9090/-/healthy 2>&1 | head -c 60; echo " <- prom 9090"
curl -s --noproxy '*' -m 5 http://localhost:3100/ready 2>&1 | head -c 60; echo " <- loki 3100"
curl -s --noproxy '*' -m 5 http://localhost:16686/ 2>&1 | head -c 60; echo " <- jaeger 16686"
curl -s --noproxy '*' -m 5 http://localhost:9202/metrics -o /dev/null -w '  prom-ex 9202: %{http_code}\n' 2>&1
echo

echo "=== 6. 磁盘 ==="
df -h /mnt/d 2>&1 | tail -1
