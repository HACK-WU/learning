#!/usr/bin/env bash
for p in $(pgrep -x consul 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
sleep 2
/mnt/d/projects/learning/consul/playground-ops/lesson03-start.sh > /dev/null 2>&1
sleep 5
echo "=== 集群就绪，开始终验 ==="
/mnt/d/projects/learning/consul/playground-ops/lesson06-verify.sh
