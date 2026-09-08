#!/usr/bin/env bash
echo "=== images ==="
docker images --format '{{.Repository}}:{{.Tag}}' | grep -Ei 'nginx|python|prometheus|victoria|minio'
echo "=== containers ==="
docker ps -a --format '{{.Names}}|{{.Status}}' | grep -Ei 'l9|rr|lesson' 
echo "=== content types in prometheus binary ==="
docker run --rm --entrypoint sh quay.io/prometheus/prometheus:v3.14.0 -c 'grep -a -o "application/x-[a-z-]*protobuf[^\"]*" /bin/prometheus | sort -u'
