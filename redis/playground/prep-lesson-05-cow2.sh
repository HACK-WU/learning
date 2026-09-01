#!/usr/bin/env bash
# 课 5 知识点 1 COW 深度实测（修正版）
# 修正：/proc/<pid>/status 中物理内存字段是 VmRSS，不是 Rss
# 原理：redis 自报的 used_memory 是"逻辑分配量"，不反映 COW 物理页复制
#       必须看内核级 VmRSS（常驻物理内存）
PORT=6405
DIR=/tmp/redis-course-l05-cow
rm -rf "$DIR"; mkdir -p "$DIR"

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1
PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
echo "Redis PID: $PID"

get_rss() {
  awk '/^VmRSS:/{print $2}' /proc/$1/status 2>/dev/null | head -1
}

gen_data() {
  # $1=数量 $2=填充字符
  python3 -c "
import sys
n=$1; ch='$2'
for i in range(1, n+1):
    val = ch * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
"
}

echo ""
echo "=== 基线：40 个 5MB key ==="
gen_data 40 x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  used_memory(逻辑): $(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+' | awk '{printf "%.1f MB", $1/1024/1024}')"
echo "  VmRSS(物理): $(get_rss $PID | awk '{printf "%.1f MB", $1/1024}')"

echo ""
echo "########## 修改比例 vs 物理内存放大 ##########"
echo "理论：COW 只复制「被修改的内存页」"
printf "%-14s %-18s %-18s %-14s\n" "修改比例" "基线VmRSS" "峰值VmRSS" "放大倍数"
printf "%-14s %-18s %-18s %-14s\n" "--------------" "------------------" "------------------" "--------------"

for pct in 0 25 50 100; do
  redis-cli -p "$PORT" flushall > /dev/null
  sleep 0.3
  gen_data 40 x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  sleep 0.5
  RB=$(get_rss $PID)

  cnt=$((40 * pct / 100))
  rm -f /tmp/l05_p.txt
  ( for i in $(seq 1 100); do
      get_rss $PID >> /tmp/l05_p.txt
      sleep 0.05
    done ) &
  MP=$!

  redis-cli -p "$PORT" bgsave > /dev/null
  sleep 0.2
  if [ "$cnt" -gt 0 ]; then
    gen_data $cnt z | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  fi
  wait $MP 2>/dev/null
  sleep 0.5

  MX=$(sort -n /tmp/l05_p.txt 2>/dev/null | tail -1)
  [ -z "$MX" ] && MX=0
  [ -z "$RB" ] && RB=1
  printf "%-14s %-18s %-18s %-14s\n" "${pct}%" \
    "$(awk -v v=$RB 'BEGIN{printf "%.1f MB", v/1024}')" \
    "$(awk -v v=$MX 'BEGIN{printf "%.1f MB", v/1024}')" \
    "$(awk -v m=$MX -v b=$RB 'BEGIN{printf "%.2fx", m/b}')"
done

echo ""
echo "########## fork 耗时 vs 数据规模（补充更大规模）##########"
printf "%-14s %-20s %-14s\n" "数据集" "latest_fork_usec" "折算"
printf "%-14s %-20s %-14s\n" "--------------" "--------------------" "--------------"
for n in 10 40 80; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" config resetstat > /dev/null
  gen_data $n x | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  U=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
  redis-cli -p "$PORT" bgsave > /dev/null
  sleep 2.5
  F=$(redis-cli -p "$PORT" info stats | grep -oP '(?<=^latest_fork_usec:)\d+')
  [ -z "$F" ] && F=0
  printf "%-14s %-20s %-14s\n" \
    "$(awk -v v=$U 'BEGIN{printf "%.0f MB", v/1024/1024}')" \
    "${F} us" \
    "$(awk -v v=$F 'BEGIN{printf "%.2f ms", v/1000}')"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null 2>&1
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -f /tmp/l05_p.txt
rm -rf "$DIR" 2>/dev/null
echo "done"
