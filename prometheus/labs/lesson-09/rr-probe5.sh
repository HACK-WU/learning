#!/usr/bin/env bash
echo "=== l9-prom-1 read endpoint reachable? ==="
docker exec l9-prom-1 wget -q -O - --post-data='' --header='Content-Type: application/x-protobuf' 'http://localhost:9090/api/v1/read' 2>&1 | head -c 300
echo ""
echo "=== which prometheus have host ports? ==="
docker ps -a --format '{{.Names}}|{{.Ports}}' | grep -E 'prom-1|prom-2|prom-rr|prom-wr'
echo "=== inspect prom-1 network ==="
docker inspect l9-prom-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{.NetworkName}}{{end}}'
echo "=== prom-1 up check via docker exec ==="
docker exec l9-prom-1 wget -q -O - 'http://localhost:9090/api/v1/query?query=up' 2>&1 | head -c 200
