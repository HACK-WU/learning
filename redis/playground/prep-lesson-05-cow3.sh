#!/usr/bin/env bash
# 课 5 COW 实测最终版：让写入贯穿整个 BGSAVE 过程
# 前面失败原因：--pipe 写入太快（毫秒级），子进程在修改开始前就已完成快照
# 解决：用后台循环持续写入，覆盖整个 BGSAVE 生命周期
PORT=6405
DIR=/tmp/redis-course-l05-cow3
rm -rf "$DIR"; mkdir -p "$DIR"

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1
PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
echo "Redis PID: $PID"

get_rss() { awk '/^VmRSS:/{print $2}' /proc/$1/status 2>/dev/null | head -1; }

# 造数据：200 个 key，每个 1MB = 约 200MB（更细的粒度便于持续写入）
gen() {
python3 -c "
n=$2; ch='$3'
for i in range($1, $1+n):
    val = ch * (1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nk:%d\r\n\$%d\r\n%s\r\n' % (len('k:%d'%i), i, len(val), val))
"
}

echo ""
echo "=== 基线：200 个 1MB key ==="
gen 1 200 x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 0.5
echo "  dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  used_memory(逻辑): $(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+' | awk '{printf "%.1f MB", $1/1024/1024}')"
RB=$(get_rss $PID)
echo "  VmRSS(物理): $(awk -v v=$RB 'BEGIN{printf "%.1f MB", v/1024}')"

echo ""
echo "########## 场景对比：BGSAVE 期间的写压力 vs 物理内存 ##########"

echo ""
echo "--- 场景 A：BGSAVE 期间【完全不写】---"
redis-cli -p "$PORT" flushall > /dev/null
gen 1 200 x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 0.5
RA=$(get_rss $PID)
rm -f /tmp/l05_a.txt
( for i in $(seq 1 200); do get_rss $PID >> /tmp/l05_a.txt; sleep 0.03; done ) & MP=$!
redis-cli -p "$PORT" bgsave > /dev/null
wait $MP 2>/dev/null
MA=$(sort -n /tmp/l05_a.txt 2>/dev/null | tail -1); [ -z "$MA" ] && MA=0
echo "  基线 $(awk -v v=$RA 'BEGIN{printf "%.1f", v/1024}') MB -> 峰值 $(awk -v v=$MA 'BEGIN{printf "%.1f", v/1024}') MB  放大 $(awk -v m=$MA -v b=$RA 'BEGIN{printf "%.2fx", m/b}')"

echo ""
echo "--- 场景 B：BGSAVE 期间【持续写入全部 200 个 key】---"
redis-cli -p "$PORT" flushall > /dev/null
gen 1 200 x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 0.5
RB2=$(get_rss $PID)
rm -f /tmp/l05_b.txt
# 后台持续监控
( for i in $(seq 1 250); do get_rss $PID >> /tmp/l05_b.txt; sleep 0.03; done ) & MP=$!
# 后台持续写入（贯穿整个快照）
( redis-cli -p "$PORT" bgsave > /dev/null
  for r in 1 2 3 4 5 6 7 8; do
    gen 1 200 "w$r" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  done ) & WP=$!
wait $WP 2>/dev/null
wait $MP 2>/dev/null
MB=$(sort -n /tmp/l05_b.txt 2>/dev/null | tail -1); [ -z "$MB" ] && MB=0
echo "  基线 $(awk -v v=$RB2 'BEGIN{printf "%.1f", v/1024}') MB -> 峰值 $(awk -v v=$MB 'BEGIN{printf "%.1f", v/1024}') MB  放大 $(awk -v m=$MB -v b=$RB2 'BEGIN{printf "%.2fx", m/b}')"

echo ""
echo "--- 场景 C：更极端的持续写入（更多轮次）---"
redis-cli -p "$PORT" flushall > /dev/null
gen 1 200 x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
sleep 0.5
RC=$(get_rss $PID)
rm -f /tmp/l05_c.txt
( for i in $(seq 1 300); do get_rss $PID >> /tmp/l05_c.txt; sleep 0.03; done ) & MP=$!
( redis-cli -p "$PORT" bgsave > /dev/null
  for r in $(seq 1 15); do
    gen 1 200 "v$r" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  done ) & WP=$!
wait $WP 2>/dev/null
wait $MP 2>/dev/null
MC=$(sort -n /tmp/l05_c.txt 2>/dev/null | tail -1); [ -z "$MC" ] && MC=0
echo "  基线 $(awk -v v=$RC 'BEGIN{printf "%.1f", v/1024}') MB -> 峰值 $(awk -v v=$MC 'BEGIN{printf "%.1f", v/1024}') MB  放大 $(awk -v m=$MC -v b=$RC 'BEGIN{printf "%.2fx", m/b}')"

echo ""
echo "########## 汇总 ##########"
printf "%-24s %-16s %-16s %-12s\n" "场景" "基线" "峰值" "放大"
printf "%-24s %-16s %-16s %-12s\n" "------------------------" "----------------" "----------------" "------------"
printf "%-24s %-16s %-16s %-12s\n" "A 不写入" \
  "$(awk -v v=$RA 'BEGIN{printf "%.1f MB", v/1024}')" "$(awk -v v=$MA 'BEGIN{printf "%.1f MB", v/1024}')" "$(awk -v m=$MA -v b=$RA 'BEGIN{printf "%.2fx", m/b}')"
printf "%-24s %-16s %-16s %-12s\n" "B 持续写入(8轮)" \
  "$(awk -v v=$RB2 'BEGIN{printf "%.1f MB", v/1024}')" "$(awk -v v=$MB 'BEGIN{printf "%.1f MB", v/1024}')" "$(awk -v m=$MB -v b=$RB2 'BEGIN{printf "%.2fx", m/b}')"
printf "%-24s %-16s %-16s %-12s\n" "C 持续写入(15轮)" \
  "$(awk -v v=$RC 'BEGIN{printf "%.1f MB", v/1024}')" "$(awk -v v=$MC 'BEGIN{printf "%.1f MB", v/1024}')" "$(awk -v m=$MC -v b=$RC 'BEGIN{printf "%.2fx", m/b}')"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null 2>&1
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -f /tmp/l05_a.txt /tmp/l05_b.txt /tmp/l05_c.txt
rm -rf "$DIR" 2>/dev/null
echo "done"
