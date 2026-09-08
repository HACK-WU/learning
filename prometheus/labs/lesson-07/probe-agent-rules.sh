#!/usr/bin/env bash
echo "########## A) agent + 混合 rules（record + alert） ##########"
docker rm -f l7-probeA 2>/dev/null >/dev/null || true
docker run --name l7-probeA --network l7net \
  -v "$(pwd)/labs/lesson-07/agent-both.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$(pwd)/labs/lesson-07/rules-both.yml:/etc/prometheus/rules.yml:ro" \
  prom/prometheus:v3.14.0 \
  --agent \
  --config.file=/etc/prometheus/prometheus.yml 2>&1 | tail -n 25
echo ">>> exitA=$?"
docker rm -f l7-probeA >/dev/null 2>&1 || true

echo
echo "########## B) agent + 仅 recording rule ##########"
docker rm -f l7-probeB 2>/dev/null >/dev/null || true
docker run --name l7-probeB --network l7net \
  -v "$(pwd)/labs/lesson-07/agent-record-only.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$(pwd)/labs/lesson-07/rules-record-only.yml:/etc/prometheus/rules-record-only.yml:ro" \
  prom/prometheus:v3.14.0 \
  --agent \
  --config.file=/etc/prometheus/prometheus.yml 2>&1 | tail -n 25
echo ">>> exitB=$?"
docker rm -f l7-probeB >/dev/null 2>&1 || true
