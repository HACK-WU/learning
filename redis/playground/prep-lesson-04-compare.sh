#!/usr/bin/env bash
# 课 4 综合：三种"计数/去重"方案的选型横评（实测）
# 场景：100 万用户的去重计数
PORT=6404
DIR=/tmp/redis-course-l04d
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1

echo "=== 场景：统计 100 万独立用户（userId 为 1..1000000 的整数）==="
echo ""

echo "--- 方案 A：Set（精确，可取成员）---"
redis-cli -p "$PORT" del uv:set > /dev/null
seq 1 1000000 | sed "s/^/sadd uv:set /" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  SCARD = $(redis-cli -p "$PORT" scard uv:set)"
echo "  编码 = $(redis-cli -p "$PORT" object encoding uv:set)"
echo "  内存 = $(redis-cli -p "$PORT" memory usage uv:set | awk '{printf "%.2f MB", $1/1024/1024}')"

echo ""
echo "--- 方案 B：Bitmap（精确，仅限整数/可映射为整数的 ID）---"
redis-cli -p "$PORT" del uv:bm > /dev/null
# 标记 100 万个位（userId 0..999999）
seq 0 999999 | sed "s/^/setbit uv:bm /;s/$/ 1/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  BITCOUNT = $(redis-cli -p "$PORT" bitcount uv:bm)"
echo "  type = $(redis-cli -p "$PORT" type uv:bm)"
echo "  内存 = $(redis-cli -p "$PORT" memory usage uv:bm | awk '{printf "%.2f MB", $1/1024/1024}')"

echo ""
echo "--- 方案 C：HyperLogLog（近似，误差 0.81%）---"
redis-cli -p "$PORT" del uv:hll > /dev/null
seq 1 1000000 | sed "s/^/pfadd uv:hll u/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  PFCOUNT = $(redis-cli -p "$PORT" pfcount uv:hll) (真实 1000000)"
echo "  误差 = $(redis-cli -p "$PORT" pfcount uv:hll | awk '{printf "%.2f%%", ($1-1000000)/1000000*100}')"
echo "  type = $(redis-cli -p "$PORT" type uv:hll)"
echo "  内存 = $(redis-cli -p "$PORT" memory usage uv:hll | awk '{printf "%.4f MB", $1/1024/1024}')"

echo ""
echo "=== 横评汇总 ==="
printf "%-14s %-12s %-14s %-12s %-10s\n" "方案" "精确?" "内存" "可取成员?" "误差"
printf "%-14s %-12s %-14s %-12s %-10s\n" "--------------" "------------" "--------------" "------------" "----------"
sm=$(redis-cli -p "$PORT" memory usage uv:set)
bm=$(redis-cli -p "$PORT" memory usage uv:bm)
hm=$(redis-cli -p "$PORT" memory usage uv:hll)
pc=$(redis-cli -p "$PORT" pfcount uv:hll)
printf "%-14s %-12s %-14s %-12s %-10s\n" "Set" "是" "$(awk "BEGIN{printf \"%.2f MB\", $sm/1024/1024}")" "是" "0%"
printf "%-14s %-12s %-14s %-12s %-10s\n" "Bitmap" "是" "$(awk "BEGIN{printf \"%.2f MB\", $bm/1024/1024}")" "否(需遍历)" "0%"
printf "%-14s %-12s %-14s %-12s %-10s\n" "HyperLogLog" "否" "$(awk "BEGIN{printf \"%.4f MB\", $hm/1024/1024}")" "否" "$(awk "BEGIN{printf \"%.2f%%\", ($pc-1000000)/1000000*100}")"

echo ""
echo "=== 空间节省倍数（相对 Set）==="
echo "  Bitmap 相对 Set 省: $(awk "BEGIN{printf \"%.1f%%\", (1-$bm/$sm)*100}")"
echo "  HLL    相对 Set 省: $(awk "BEGIN{printf \"%.2f%%\", (1-$hm/$sm)*100}")"
echo "  HLL    相对 Set 倍数: $(awk "BEGIN{printf \"%.0fx\", $sm/$hm}")"

echo ""
echo "=== Bitmap 的空间陷阱：稀疏 ID 会撑爆内存 ==="
redis-cli -p "$PORT" del uv:sparse > /dev/null
# 只有 10 个元素，但其中一个 offset 是 1 亿
for i in 1 2 3 4 5 6 7 8 9; do redis-cli -p "$PORT" setbit uv:sparse $i 1 > /dev/null; done
redis-cli -p "$PORT" setbit uv:sparse 100000000 1 > /dev/null
echo "  只存了 10 个元素，但最大 offset = 100000000"
echo "  BITCOUNT = $(redis-cli -p "$PORT" bitcount uv:sparse)"
echo "  内存 = $(redis-cli -p "$PORT" memory usage uv:sparse | awk '{printf "%.2f MB", $1/1024/1024}')  <-- 约 12.5 MB！"
echo "  对比 Set 存同样 10 个整数:"
redis-cli -p "$PORT" del uv:s10 > /dev/null
for i in 1 2 3 4 5 6 7 8 9 100000000; do redis-cli -p "$PORT" sadd uv:s10 $i > /dev/null; done
echo "  Set 内存 = $(redis-cli -p "$PORT" memory usage uv:s10) 字节"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
