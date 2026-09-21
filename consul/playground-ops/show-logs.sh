#!/usr/bin/env bash
BASE=/tmp/consul-ops
for i in 1 2 3; do
  echo "===== node$i ====="
  tail -20 "$BASE/log/node$i.log" 2>/dev/null || echo "no log"
done
