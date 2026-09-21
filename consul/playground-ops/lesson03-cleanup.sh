#!/usr/bin/env bash
for p in $(pgrep -x consul 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
sleep 2
echo "consul 进程 = $(pgrep -x consul 2>/dev/null | wc -l)"
rm -rf /tmp/consul-ops/data /tmp/bigval.bin /tmp/f 2>/dev/null
echo "临时数据已清理"
