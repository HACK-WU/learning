#!/bin/bash
echo "=== counts ==="
docker exec l5-prom wget -qO- "http://l5-receiver:8099/count"
echo ""
echo "=== payments ==="
docker exec l5-prom wget -qO- "http://l5-receiver:8099/list?path=payments"
echo ""
echo "=== default ==="
docker exec l5-prom wget -qO- "http://l5-receiver:8099/list?path=default"
echo ""
echo "=== prom alerts ==="
docker exec l5-prom wget -qO- "http://localhost:9090/api/v1/alerts" | head -c 300
echo ""
echo "=== am alerts ==="
docker exec l5-prom wget -qO- "http://l5-am:9093/api/v2/alerts" | head -c 300
