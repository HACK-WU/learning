#!/usr/bin/env bash
# 安全重建：不用 pkill -f（会误杀自身 shell），按 pid 精确杀
BASE=/tmp/consul-ops
for p in $(pgrep -x consul 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
sleep 3
echo "残留 consul 进程 = $(pgrep -x consul 2>/dev/null | wc -l)"
for i in 1 2 3; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null; done
echo "lo 地址: $(ip -4 addr show lo | grep -oE '127\.0\.0\.[0-9]+' | sort -u | tr '\n' ' ')"
rm -rf "$BASE/data" "$BASE/log"
mkdir -p "$BASE"/data/node{1,2,3} "$BASE"/conf "$BASE"/log
echo "目录重建完成: $(ls -d $BASE/data/node* | tr '\n' ' ')"
