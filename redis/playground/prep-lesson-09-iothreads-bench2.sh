#!/bin/bash
# 用官方 redis-benchmark（C 实现）重测 io-threads，排除 Python 客户端瓶颈
echo "=== redis-benchmark 可用性 ==="
which redis-benchmark
redis-benchmark --version 2>&1 | head -2

echo ""
echo "=== 关键：io 线程是否真的被激活 ==="
echo "先看压测前的计数（应均为 0）:"
for p in 7102 7103 7104; do
  echo -n "  7102/7103/7104 $p: "
  redis-cli -p $p info stats 2>/dev/null | grep -E "io_threaded" | tr '\n' ' '
  echo ""
done

echo ""
echo "=== 回环网络 MTU 与 CPU ==="
ip link show lo 2>/dev/null | head -2
nproc
echo "--- 物理核（排除超线程） ---"
lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort -u | wc -l
