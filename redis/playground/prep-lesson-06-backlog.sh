#!/usr/bin/env bash
# 课 6 backlog 机制直接观测：不依赖"断线重连"，直接看 offset 与 histlen 的关系
# 本机回环网络重连太快（毫秒级），撑不爆 backlog，改用直接观测机制
# 原理：主库维护全局 master_repl_offset；backlog 是环形缓冲，只保留最近 N 字节
#       从库报上来的 slave_repl_offset 若 < backlog 起点，则无法 partial -> 全量
BASE=/tmp/redis-course-l06-bl
rm -rf "$BASE"; mkdir -p "$BASE"
M=6401; S=6402

redis-server --port $M --daemonize yes --save '' --appendonly no --dir "$BASE" --logfile "$BASE/m.log" > /dev/null 2>&1
mkdir -p "$BASE/s"
redis-server --port $S --daemonize yes --save '' --appendonly no --dir "$BASE/s" --logfile "$BASE/s.log" > /dev/null 2>&1
sleep 1
redis-cli -p $M config set repl-diskless-sync-delay 0 > /dev/null

gen() {
python3 -c "
n=$1; pre='$2'; sz=$3
for i in range(1, n+1):
    val = 'v' * sz
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\n%s:%d\r\n\$%d\r\n%s\r\n' % (len('%s:%d'%(pre,i)), pre, i, len(val), val))
"
}

gen 20000 base 20 | redis-cli -p $M --pipe > /dev/null 2>&1
redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
sleep 3

echo "########## 1. backlog 环形缓冲的直接观测 ##########"
echo ""
echo "  设置 backlog = 1MB（默认），持续写入直到 histlen 饱和"
redis-cli -p $M config set repl-backlog-size 1mb > /dev/null
sleep 0.5

printf "%-22s %-16s %-16s %-16s\n" "阶段" "master_offset" "backlog_histlen" "backlog起点"
printf "%-22s %-16s %-16s %-16s\n" "----------------------" "----------------" "----------------" "----------------"

show() {
  local l=$1
  local off=$(redis-cli -p $M info replication | grep -oP '(?<=^master_repl_offset:)\d+')
  local hl=$(redis-cli -p $M info replication | grep -oP '(?<=^repl_backlog_histlen:)\d+')
  local fb=$(redis-cli -p $M info replication | grep -oP '(?<=^repl_backlog_first_byte_offset:)\d+')
  printf "%-22s %-16s %-16s %-16s\n" "$l" "$off" "$hl" "$fb"
}

show "初始"
gen 5000 w1 200 | redis-cli -p $M --pipe > /dev/null 2>&1; show "写入 5000 条后"
gen 20000 w2 200 | redis-cli -p $M --pipe > /dev/null 2>&1; show "再写 2 万条"
gen 50000 w3 500 | redis-cli -p $M --pipe > /dev/null 2>&1; show "再写 5 万条(大value)"

echo ""
echo "  >>> 关键观察：backlog_histlen 达到 repl_backlog_size 后不再增长（环形缓冲满）"
echo "  >>> 而 master_repl_offset 持续增长 -> 两者差值 = 「已挤出 backlog 的字节数」"

echo ""
echo "########## 2. 定量：backlog 能容忍多久的断线 ##########"
echo ""
echo "  实测：写入速率 vs backlog 耗尽时间"
redis-cli -p $M config set repl-backlog-size 1mb > /dev/null
sleep 0.5
# 让 histlen 饱和
gen 100000 sat 500 | redis-cli -p $M --pipe > /dev/null 2>&1
H0=$(redis-cli -p $M info replication | grep -oP '(?<=^repl_backlog_histlen:)\d+')
SZ=$(redis-cli -p $M config get repl-backlog-size | tail -1)
echo "  当前 histlen=$H0 / size=$SZ ($(awk -v v=$SZ 'BEGIN{printf "%.0f MB", v/1024/1024}'))"

echo ""
echo "  测不同写入速率下 backlog 的耗尽时间："
printf "%-26s %-22s %-22s\n" "写入速率" "耗尽 1MB 耗时" "说明"
printf "%-26s %-22s %-22s\n" "--------------------------" "----------------------" "----------------------"

# 用 redis-benchmark 测吞吐，然后换算
TPS=$(redis-benchmark -p $M -n 20000 -c 10 -t set -q 2>/dev/null | grep -oP 'SET: \K[\d.]+')
echo "  实测本机 SET 吞吐: $TPS ops/s"
echo ""
echo "  换算（假设每条命令平均 100 字节）："
for rate in 1000 10000 50000; do
  T=$(awk -v sz=1048576 -v r=$rate 'BEGIN{printf "%.1f 秒", sz/(r*100)}')
  printf "%-26s %-22s %-22s\n" "$rate 写/秒" "$T" "-"
done
echo "  满载($TPS 写/秒) 时: $(awk -v sz=1048576 -v r=$TPS 'BEGIN{printf "%.3f 秒", sz/(r*100)}')"

echo ""
echo "########## 3. 调大 backlog 的效果 ##########"
printf "%-16s %-20s %-22s\n" "backlog 大小" "1MB=1048576B" "满载耗尽耗时"
printf "%-16s %-20s %-22s\n" "----------------" "--------------------" "----------------------"
for sz in 1mb 16mb 64mb 256mb; do
  B=$(echo $sz | sed 's/mb//')
  BYTES=$((B * 1024 * 1024))
  T=$(awk -v s=$BYTES -v r=$TPS 'BEGIN{printf "%.2f 秒", s/(r*100)}')
  printf "%-16s %-20s %-22s\n" "$sz" "$BYTES 字节" "$T"
done

echo ""
echo "########## 4. 从库 offset 落后主库多少（复制延迟量化）##########"
gen 30000 lag 300 | redis-cli -p $M --pipe > /dev/null 2>&1
sleep 0.2
MO=$(redis-cli -p $M info replication | grep -oP '(?<=^master_repl_offset:)\d+')
SO=$(redis-cli -p $S info replication | grep -oP '(?<=^slave_repl_offset:)\d+')
echo "  写入中: master_offset=$MO  slave_offset=$SO  差值=$((MO-SO)) 字节"
sleep 2
MO2=$(redis-cli -p $M info replication | grep -oP '(?<=^master_repl_offset:)\d+')
SO2=$(redis-cli -p $S info replication | grep -oP '(?<=^slave_repl_offset:)\d+')
echo "  静止后: master_offset=$MO2  slave_offset=$SO2  差值=$((MO2-SO2)) 字节"

echo ""
echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
