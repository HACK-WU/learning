#!/usr/bin/env bash
docker run --rm --entrypoint sh quay.io/prometheus/prometheus:v3.14.0 -c 'grep -a -o -i "streamed[a-z_]*" /bin/prometheus | sort | uniq -c'
echo "=== frame flag ==="
docker run --rm --entrypoint sh quay.io/prometheus/prometheus:v3.14.0 -c 'grep -a -o "read-max-bytes-in-frame" /bin/prometheus | head -1'
echo "=== accept negotiation ==="
docker run --rm --entrypoint sh quay.io/prometheus/prometheus:v3.14.0 -c 'grep -a -o "Accept: [^\"]\{0,80\}" /bin/prometheus | sort -u | head -20'
