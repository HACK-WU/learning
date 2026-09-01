#!/usr/bin/env bash
# 课 5 知识点 1 修正版：fork 耗时与 COW 内存放大实测
# 关键修正：redis-cli set 无法处理超长值，必须用 --pipe 批量写入
PORT=6405
DIR=/tmp/redis-course-l05-fork
rm -rf "$DIR"; mkdir -p "$DIR"

redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" --maxmemory 0 > /dev/null 2>&1
sleep 1

echo "=== 构造数据集（用 --pipe 批量写入）==="
# 每个 key 约 5MB，共 40 个 = 约 200MB
python3 - <<'PYEOF' > /tmp/l05_bigdata.txt
# 生成 40 个 key，每个 value 5MB
for i in range(1, 41):
    val = 'x' * (5 * 1024 * 1024)
    print("*3\r\n$3\r\nSET\r\n$%d\r\nbigkey:%d\r\n$%d\r\n%s\r\n" % (len(f'bigkey:{i}'), i, len(val), val))
PYEOF
wc -c /tmp/l05_bigdata.txt | awk '{print "  待写入命令文件: " $1/1024/1024 " MB"}'
redis-cli -p "$PORT" --pipe < /tmp/l05_bigdata.txt 2>&1 | tail -2

USED=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
echo "  dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  used_memory: $(awk "BEGIN{printf \"%.1f MB\", $USED/1024/1024}")"

echo ""
echo "########## fork 耗时实测（不同数据规模）##########"
printf "%-16s %-18s %-18s\n" "数据集大小" "latest_fork_usec" "折算"
printf "%-16s %-18s %-18s\n" "----------------" "------------------" "------------------"

for n in 5 20 40; do
  redis-cli -p "$PORT" flushall > /dev/null
  redis-cli -p "$PORT" config resetstat > /dev/null
  # 写入 n 个大 key
  python3 -c "
for i in range(1, $n+1):
    val = 'x' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  U=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
  redis-cli -p "$PORT" bgsave > /dev/null
  sleep 2
  F=$(redis-cli -p "$PORT" info stats | grep -oP '(?<=^latest_fork_usec:)\d+')
  printf "%-16s %-18s %-18s\n" \
    "$(awk "BEGIN{printf \"%.0f MB\", $U/1024/1024}")" \
    "${F} us" \
    "$(awk "BEGIN{printf \"%.2f ms\", $F/1000}")"
done

echo ""
echo "########## COW 内存放大实测 ##########"
echo "场景：BGSAVE 期间，父进程修改全部 key，触发最大 COW"
echo ""

redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" config resetstat > /dev/null
# 写入 40 个 5MB key
python3 -c "
for i in range(1, 41):
    val = 'x' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1

BASE=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
echo "  基线 used_memory: $(awk "BEGIN{printf \"%.1f MB\", $BASE/1024/1024}")"

# 后台持续监控内存
( for i in $(seq 1 60); do
    redis-cli -p "$PORT" info memory 2>/dev/null | grep -oP '(?<=^used_memory:)\d+' >> /tmp/l05_mem_watch.txt
    sleep 0.2
  done ) &
MONPID=$!
rm -f /tmp/l05_mem_watch.txt

# 发起 BGSAVE
redis-cli -p "$PORT" bgsave > /dev/null
sleep 0.3

# 立即修改全部 40 个 key，触发最大 COW
python3 -c "
for i in range(1, 41):
    val = 'y' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1

wait $MONPID 2>/dev/null
sleep 1

PEAK=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory_peak:)\d+')
MAXW=$(sort -n /tmp/l05_mem_watch.txt 2>/dev/null | tail -1)
echo "  快照+写入期间观测到的最大 used_memory: $(awk "BEGIN{printf \"%.1f MB\", ${MAXW:-0}/1024/1024}")"
echo "  used_memory_peak: $(awk "BEGIN{printf \"%.1f MB\", $PEAK/1024/1024}")"
echo "  相对基线放大: $(awk "BEGIN{printf \"%.2fx\", ${MAXW:-$BASE}/$BASE}")"

echo ""
echo "  --- 对照：BGSAVE 期间不写入 ---"
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" config resetstat > /dev/null
python3 -c "
for i in range(1, 41):
    val = 'x' * (5*1024*1024)
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\nbigkey:%d\r\n\$%d\r\n%s\r\n' % (len('bigkey:%d'%i), i, len(val), val))
" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
B2=$(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')
( for i in $(seq 1 30); do
    redis-cli -p "$PORT" info memory 2>/dev/null | grep -oP '(?<=^used_memory:)\d+' >> /tmp/l05_mem_watch2.txt
    sleep 0.2
  done ) &
MONPID2=$!
rm -f /tmp/l05_mem_watch2.txt
redis-cli -p "$PORT" bgsave > /dev/null
wait $MONPID2 2>/dev/null
MAXW2=$(sort -n /tmp/l05_mem_watch2.txt 2>/dev/null | tail -1)
echo "  基线: $(awk "BEGIN{printf \"%.1f MB\", $B2/1024/1024}")"
echo "  快照期间最大: $(awk "BEGIN{printf \"%.1f MB\", ${MAXW2:-0}/1024/1024}")"
echo "  放大: $(awk "BEGIN{printf \"%.2fx\", ${MAXW2:-$B2}/$B2}")  <-- 不写入时几乎不涨"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null 2>&1
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rm -f /tmp/l05_bigdata.txt /tmp/l05_mem_watch.txt /tmp/l05_mem_watch2.txt
rm -rf "$DIR" 2>/dev/null
echo "done"
