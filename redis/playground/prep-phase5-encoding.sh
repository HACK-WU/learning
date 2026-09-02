#!/bin/bash
# 评审 B 类证据核查：ZSet 从 listpack 转 skiplist 时，内存到底跳变多少倍？
# 目的：10-场景解法库 场景3 断言"内存占用跳变接近翻倍"，需实测支撑，否则属于无证据断言。
set -u
PORT=7203
R="redis-cli -p $PORT"

echo "=== ZSet 编码转换的内存跳变实测（阈值 zset-max-listpack-entries=128）==="
$R DEL bench:zset > /dev/null 2>&1

prev_size=""
for n in 100 128 129 200 500; do
  # 只增不减，逐段填充到目标规模
  $R DEL bench:zset > /dev/null 2>&1
  for ((i=1; i<=n; i++)); do
    echo "ZADD bench:zset $i member_$i"
  done | $R --pipe > /dev/null 2>&1

  enc=$($R OBJECT ENCODING bench:zset 2>/dev/null | tr -d '\r')
  size=$($R MEMORY USAGE bench:zset 2>/dev/null | tr -d '\r')
  per=$(awk "BEGIN{printf \"%.1f\", $size/$n}")
  printf "  n=%-5s 编码=%-10s 总内存=%-8s 每元素=%-8s\n" "$n" "$enc" "$size" "$per"

  if [ "$n" = "128" ]; then prev_size=$size; fi
  if [ "$n" = "129" ]; then
    if [ -n "$prev_size" ] && [ "$prev_size" -gt 0 ] 2>/dev/null; then
      ratio=$(awk "BEGIN{printf \"%.2f\", $size/$prev_size}")
      echo "    → 128→129 跨越阈值：总内存 ${prev_size} → ${size}，跳变 ${ratio} 倍"
    fi
  fi
done

$R DEL bench:zset > /dev/null 2>&1
echo "  已清理 bench:zset"
