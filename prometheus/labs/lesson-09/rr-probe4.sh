#!/usr/bin/env bash
echo "=== python snappy availability ==="
docker run --rm python:3.11-slim python -c "import snappy; print('snappy OK')" 2>&1 | tail -2
docker run --rm python:3.11-slim pip install cramjam 2>&1 | tail -3
echo "=== current data scale in l9-prom-1 ==="
curl -s 'http://localhost:19090/api/v1/query?query=count(app_requests_total)' 
echo ""
docker exec l9-prom-1 sh -c 'ls -la /prometheus/ 2>/dev/null | head -5'
echo "=== ports ==="
docker ps --format '{{.Names}}|{{.Ports}}' | grep l9
