#!/usr/bin/env bash
set -euo pipefail
BASE=/tmp/consul-ops

for i in 1 2 3; do
  nohup consul agent -config-file "$BASE/conf/node$i.hcl" \
    > "$BASE/log/node$i.log" 2>&1 &
  echo "started node$i pid=$!"
done

sleep 15
echo "=== processes ==="
pgrep -af 'consul agent' || echo "NONE RUNNING"
