#!/bin/bash
echo "=== 1. Alertmanager ready ==="
docker exec l5-am wget -qO- http://localhost:9093/-/ready 2>&1 | head -3

echo ""
echo "=== 2. AM config loaded (routes receivers) ==="
docker exec l5-am wget -qO- http://localhost:9093/api/v2/status 2>&1 | head -c 600
echo ""

echo ""
echo "=== 3. Prometheus targets ==="
docker exec l5-prom wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>&1 \
  | python3 -c "import sys,json; d=json.load(sys.stdin); [print(t['labels'].get('job'), t['scrapeUrl'], t['health']) for t in d['data']['activeTargets']]" 2>&1

echo ""
echo "=== 4. Prometheus -> Alertmanager discovery ==="
docker exec l5-prom wget -qO- http://localhost:9090/api/v1/alertmanagers 2>&1 | head -c 400
echo ""

echo ""
echo "=== 5. receiver reachable from AM ==="
docker exec l5-am wget -qO- http://l5-receiver:8099/count 2>&1 | head -3
echo ""

echo ""
echo "=== 6. app metrics sample ==="
docker exec l5-prom wget -qO- 'http://l5-app-1:8080/metrics' 2>&1 | grep -E '^app_(node_up|error_rate_target)' | head -5
