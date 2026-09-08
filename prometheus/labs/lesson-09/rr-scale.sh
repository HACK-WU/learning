#!/usr/bin/env bash
echo "=== current series count ==="
docker exec l9-prom-1 wget -q -O - 'http://localhost:9090/api/v1/query?query=count(app_requests_total)' 2>&1 | head -c 200
echo ""
echo "=== check app metric cardinality ==="
docker exec l9-prom-1 wget -q -O - 'http://localhost:9090/api/v1/query?query=count(count%20by(route,status,instance)(app_requests_total))' 2>&1 | head -c 200
echo ""
echo "=== all metric names ==="
docker exec l9-prom-1 wget -q -O - 'http://localhost:9090/api/v1/label/__name__/values' 2>&1 | head -c 500
