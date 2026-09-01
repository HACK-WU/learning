#!/usr/bin/env bash
# 课 5 知识点 1 深度实测：COW 真实内存放大
# 关键修正：redis 自报的 used_memory 是"逻辑分配量"，不反映 COW 导致的物理页复制
# 必须看内核级指标：/proc/<pid>/smaps_rollup 的 Private_Dirty + Shared，或 Rss
PORT=6405
DIR=/tmp/redis-course-l05-cow
rm -rf "$DIR"; mkdir -p "$DIR"

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1
PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
echo "Redis PID: $PID"
echo ""

echo "=== 基线：写入 40 个 5MB key（约 200MB）==="
python3 -c "
for i in range(1, 41):
    val = 'x' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  used_memory: $(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+' | awk '{printf "%.1f MB", $1/1024/1024}')"
echo "  内核 Rss: $(grep -oP '(?<=^Rss:)\s*\d+' /proc/$PID/status 2>/dev/null | tr -d ' ' | awk '{printf "%.1f MB", $1/1024}')"

# 精确读取物理内存的函数
get_rss() {
  local p=$1
  awk '/^Rss:/{print $2}' /proc/$p/status 2>/dev/null || echo 0
}
get_pss() {
  local p=$1
  grep -oP '(?<=^Pss:)\s*\d+' /proc/$p/smaps_rollup 2>/dev/null | tr -d ' ' || echo 0
}

echo ""
echo "########## COW 实测：BGSAVE 期间修改全部 key ##########"
RSS0=$(get_rss $PID)
echo "  快照前 Rss: $(awk "BEGIN{printf \"%.1f MB\", $RSS0/1024}")"

# 高频监控（50ms 一次）
rm -f /tmp/l05_cow_rss.txt
( for i in $(seq 1 120); do
    awk '/^Rss:/{print $2}' /proc/$PID/status 2>/dev/null >> /tmp/l05_cow_rss.txt
    sleep 0.05
  done ) &
MONPID=$!

# 发起 BGSAVE
redis-cli -p "$PORT" bgsave > /dev/null
sleep 0.2

# 立即修改全部 40 个 key（每个 5MB），最大化 COW
python3 -c "
for i in range(1, 41):
    val = 'y' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1

wait $MONPID 2>/dev/null
sleep 1

RSS1=$(get_rss $PID)
MAXRSS=$(sort -n /tmp/l05_cow_rss.txt 2>/dev/null | tail -1)
echo "  快照后 Rss: $(awk "BEGIN{printf \"%.1f MB\", $RSS1/1024}")"
echo "  期间最大 Rss: $(awk "BEGIN{printf \"%.1f MB\", ${MAXRSS:-0}/1024}")"
echo "  物理内存放大: $(awk "BEGIN{printf \"%.2fx\", ${MAXRSS:-$RSS0}/$RSS0}")"

# 子进程信息
echo ""
echo "=== fork 出的子进程（应已退出）==="
ps -ef | grep "[r]edis-server.*$PORT" | head -3

echo ""
echo "########## 对照：不写入时 BGSAVE 的物理内存 ##########"
redis-cli -p "$PORT" flushall > /dev/null
python3 -c "
for i in range(1, 41):
    val = 'x' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
RSS2=$(get_rss $PID)
echo "  基线 Rss: $(awk "BEGIN{printf \"%.1f MB\", $RSS2/1024}")"
rm -f /tmp/l05_cow_rss2.txt
( for i in $(seq 1 80); do
    awk '/^Rss:/{print $2}' /proc/$PID/status 2>/dev/null >> /tmp/l05_cow_rss2.txt
    sleep 0.05
  done ) &
MONPID2=$!
redis-cli -p "$PORT" bgsave > /dev/null
wait $MONPID2 2>/dev/null
MAXRSS2=$(sort -n /tmp/l05_cow_rss2.txt 2>/dev/null | tail -1)
echo "  期间最大 Rss: $(awk "BEGIN{printf \"%.1f MB\", ${MAXRSS2:-0}/1024}")"
echo "  放大: $(awk "BEGIN{printf \"%.2fx\", ${MAXRSS2:-$RSS2}/$RSS2}")"

echo ""
echo "########## 关键：单次 BGSAVE 期间修改比例 vs 内存放大 ##########"
echo "理论上：COW 只复制「被修改的页」，不是全部内存"
printf "%-16s %-16s %-16s\n" "修改比例" "最大Rss(MB)" "放大倍数"
printf "%-16s %-16s %-16s\n" "----------------" "----------------" "----------------"

for pct in 0 25 50 100; do
  redis-cli -p "$PORT" flushall > /dev/null
  python3 -c "
for i in range(1, 41):
    val = 'x' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  RB=$(get_rss $PID)
  cnt=$((40 * pct / 100))
  rm -f /tmp/l05_cow_p.txt
  ( for i in $(seq 1 100); do
      awk '/^Rss:/{print $2}' /proc/$PID/status 2>/dev/null >> /tmp/l05_cow_p.txt
      sleep 0.05
    done ) &
  MP=$!
  redis-cli -p "$PORT" bgsave > /dev/null
  sleep 0.2
  if [ "$cnt" -gt 0 ]; then
    python3 -c "
for i in range(1, $cnt+1):
    val = 'z' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  fi
  wait $MP 2>/dev/null
  sleep 0.5
  MX=$(sort -n /tmp/l05_cow_p.txt 2>/dev/null | tail -1)
  printf "%-16s %-16s %-16s\n" "${pct}%" \
    "$(awk "BEGIN{printf \"%.1f\", ${MX:-0}/1024}")" \
    "$(awk "BEGIN{printf \"%.2fx\", ${MX:-$RB}/$RB}")"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null 2>&1
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -f /tmp/l05_cow_rss.txt /tmp/l05_cow_rss2.txt /tmp/l05_cow_p.txt
rm -rf "$DIR" 2>/dev/null
echo "done"
