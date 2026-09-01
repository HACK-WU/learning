#!/usr/bin/env bash
# 课 4 知识点 2 补充：ZSet 双结构的规模梯度实测
# 用 redis-cli --latency 无关手段：直接循环计时，对比不同规模下的单次耗时
PORT=6404
DIR=/tmp/redis-course-l04b2
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== 构造不同规模的 ZSet，测 ZSCORE（哈希表 O(1)）与 ZREVRANK（跳表 O(logN)）==="
echo ""
printf "%-10s %-18s %-18s %-12s\n" "规模" "ZSCORE(ms)" "ZREVRANK(ms)" "编码"
printf "%-10s %-18s %-18s %-12s\n" "----------" "------------------" "------------------" "------------"

for n in 10000 100000 500000 1000000; do
  key="z:g:$n"
  redis-cli -p "$PORT" del "$key" > /dev/null
  seq 1 "$n" | awk -v k="$key" '{print "zadd "k" "$1" m"$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  enc=$(redis-cli -p "$PORT" object encoding "$key")
  mid=$((n/2))
  member="m$mid"

  # ZSCORE 测 200 次取总耗时
  s=$(date +%s%N)
  for i in $(seq 1 200); do redis-cli -p "$PORT" zscore "$key" "$member" > /dev/null; done
  e=$(date +%s%N)
  zscore_ms=$(awk "BEGIN{printf \"%.4f\", ($e-$s)/200/1000000}")

  # ZREVRANK 测 200 次取总耗时
  s=$(date +%s%N)
  for i in $(seq 1 200); do redis-cli -p "$PORT" zrevrank "$key" "$member" > /dev/null; done
  e=$(date +%s%N)
  zrevrank_ms=$(awk "BEGIN{printf \"%.4f\", ($e-$s)/200/1000000}")

  printf "%-10s %-18s %-18s %-12s\n" "$n" "$zscore_ms" "$zrevrank_ms" "$enc"
done

echo ""
echo "=== 对照：List 的 LINDEX（课 3 结论是 O(N)），同样梯度 ==="
printf "%-10s %-18s\n" "规模" "LINDEX 中间(ms)"
printf "%-10s %-18s\n" "----------" "------------------"
for n in 10000 100000 500000 1000000; do
  key="l:g:$n"
  redis-cli -p "$PORT" del "$key" > /dev/null
  # 用 RPUSH 一次性推入（分块避免参数过长）
  seq 1 "$n" | sed "s/^/v/" | awk -v k="$key" '{print "rpush "k" "$1}' | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  mid=$((n/2))
  s=$(date +%s%N)
  for i in $(seq 1 50); do redis-cli -p "$PORT" lindex "$key" "$mid" > /dev/null; done
  e=$(date +%s%N)
  lindex_ms=$(awk "BEGIN{printf \"%.4f\", ($e-$s)/50/1000000}")
  printf "%-10s %-18s\n" "$n" "$lindex_ms"
done

echo ""
echo "=== 内存占用对比（ZSet vs List，100 万元素）==="
echo "ZSet z:g:1000000 内存: $(redis-cli -p "$PORT" memory usage z:g:1000000 | awk '{printf "%.2f MB", $1/1024/1024}')"
echo "List l:g:1000000 内存: $(redis-cli -p "$PORT" memory usage l:g:1000000 | awk '{printf "%.2f MB", $1/1024/1024}')"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
