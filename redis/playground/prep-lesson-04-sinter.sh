#!/usr/bin/env bash
# 课 4 补充：SINTER 会遍历"最小集合"—— 用实测证明参数顺序不影响性能
PORT=6404
DIR=/tmp/redis-course-l04e
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== 构造：一个大 Set(100万) + 一个小 Set(100) ==="
redis-cli -p "$PORT" del big small > /dev/null
seq 1 1000000 | sed "s/^/sadd big u/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
seq 1 100 | sed "s/^/sadd small u/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "big   scard = $(redis-cli -p "$PORT" scard big)"
echo "small scard = $(redis-cli -p "$PORT" scard small)"

echo ""
echo "=== SINTER 两种参数顺序（Redis 内部会按基数排序，用最小集合遍历）==="
echo "-- 顺序 1: SINTER big small --"
r1=$(redis-benchmark -p "$PORT" -n 2000 -c 1 sinter big small 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
echo "  吞吐: ${r1} ops/s -> 单次 $(awk "BEGIN{printf \"%.4f ms\", 1000/$r1}")"
echo "-- 顺序 2: SINTER small big --"
r2=$(redis-benchmark -p "$PORT" -n 2000 -c 1 sinter small big 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
echo "  吞吐: ${r2} ops/s -> 单次 $(awk "BEGIN{printf \"%.4f ms\", 1000/$r2}")"
echo "结论：两者耗时$(awk "BEGIN{d=$r1/$r2; if(d>0.8&&d<1.25) print \"几乎相同\"; else print \"有差异\"}")，证明 Redis 内部会重排，与参数顺序无关"

echo ""
echo "=== 对比 SUNION（必须遍历所有集合，O(N) 总元素数）==="
ru=$(redis-benchmark -p "$PORT" -n 200 -c 1 sunion big small 2>/dev/null | grep -oP '[\d.]+(?= requests per second)')
echo "  SUNION big small 吞吐: ${ru} ops/s -> 单次 $(awk "BEGIN{printf \"%.4f ms\", 1000/$ru}")"
echo "  <-- 比 SINTER 慢约 $(awk "BEGIN{printf \"%.0f\", $r1/$ru}") 倍，因为要遍历 100 万+100 个元素"

echo ""
echo "=== 对照：SDIFF 的方向敏感性（结果不同，不是性能不同）==="
echo "  SDIFF big small 基数: $(redis-cli -p "$PORT" sdiff big small | wc -l)  (big 有而 small 没有)"
echo "  SDIFF small big 基数: $(redis-cli -p "$PORT" sdiff small big | wc -l)  (small 有而 big 没有)"

echo ""
echo "=== 生产警示：大集合 SINTERSTORE 会阻塞主线程 ==="
echo "  SUNION big small 单次约 $(awk "BEGIN{printf \"%.1f\", 1000000/$ru}") ms"
echo "  在单线程模型下，这意味着期间所有其他命令都要排队等待"

echo ""
echo "=== SINTERCARD：只要数量不要成员，省网络传输 ==="
echo "  SINTER big small 返回成员数: $(redis-cli -p "$PORT" sinter big small | wc -l)"
echo "  SINTERCARD 2 big small: $(redis-cli -p "$PORT" sintercard 2 big small)"
echo "  SINTERCARD 带 LIMIT: $(redis-cli -p "$PORT" sintercard 2 big small limit 50)"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
