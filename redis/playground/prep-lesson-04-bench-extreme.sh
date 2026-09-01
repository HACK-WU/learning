#!/usr/bin/env bash
# 课 4 知识点 2 补充：用极端规模差（1万 vs 500万）让 O(logN) 与 O(N) 差异显性化
# 前提：pipeline=50 已摊薄 RTT，单次耗时 ≈ 命令真实 CPU 时间
PORT=6404
DIR=/tmp/redis-course-l04b7
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1

echo "=== 构造 1 万 与 500 万 两个极端规模 ==="
for n in 10000 5000000; do
  zkey="z:X:$n"
  redis-cli -p "$PORT" del "$zkey" > /dev/null
  seq 1 "$n" | awk -v k="$zkey" '{print "zadd "k" "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  echo "  ZSet $n 成员: zcard=$(redis-cli -p "$PORT" zcard "$zkey"), 编码=$(redis-cli -p "$PORT" object encoding "$zkey")"
done

echo ""
echo "=== ZSCORE (O(1) 哈希表) 与 ZREVRANK (O(logN) 跳表) 对比 ==="
printf "%-12s %-18s %-18s\n" "规模" "ZSCORE(us)" "ZREVRANK(us)"
printf "%-12s %-18s %-18s\n" "------------" "------------------" "------------------"
for n in 10000 5000000; do
  zkey="z:X:$n"; mid=$((n/2))
  zs=$(redis-benchmark -p "$PORT" -n 300000 -c 1 -P 50 zscore "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  zr=$(redis-benchmark -p "$PORT" -n 300000 -c 1 -P 50 zrevrank "$zkey" "m$mid" 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
  printf "%-12s %-18s %-18s\n" "$n" \
    "$(awk "BEGIN{printf \"%.3f us\", 1000000/$zs}")" \
    "$(awk "BEGIN{printf \"%.3f us\", 1000000/$zr}")"
done

echo ""
echo "=== 理论预测对照 ==="
echo "  规模 1万 -> 500万：N 增长 500 倍"
echo "  O(1)   理论增长：1.00x（不随 N 变）"
echo "  O(logN)理论增长：log2(5000000)/log2(10000) = $(awk "BEGIN{printf \"%.2f\", (log(5000000)/log(2))/(log(10000)/log(2))}")x"
echo "  O(N)   理论增长：500x"

echo ""
echo "=== 跳表层数证据：用 DEBUG 查看 skiplist 结构（需 enable-debug-command）==="
redis-cli -p "$PORT" config get enable-debug-command 2>/dev/null | tail -1

echo ""
echo "=== 内存换速度：ZSet 双结构的内存代价（500万）==="
echo "  ZSet 500万 内存: $(redis-cli -p "$PORT" memory usage z:X:5000000 | awk '{printf "%.1f MB", $1/1024/1024}')"
echo "  每个成员平均: $(redis-cli -p "$PORT" memory usage z:X:5000000 | awk '{printf "%.1f 字节", $1/5000000}')"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
