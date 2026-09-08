#!/usr/bin/env bash
echo "=== app.py exists? ==="
ls -la /mnt/d/projects/learning/prometheus/labs/lesson-09/app/
echo "=== app reachable from prom-1? ==="
docker exec l9-prom-1 wget -q -O - 'http://l9-app:8000/metrics' 2>&1 | head -c 300
echo ""
echo "=== prom-1 config: does it have remote write receiver flag? ==="
docker inspect l9-prom-1 --format '{{range .Args}}{{.}} {{end}}'
