#!/usr/bin/env bash
# 课 6 增量复制验证（方法三）：CLIENT KILL 切断复制连接
# 前两种方法失败原因分析：
#   1. replicaof no one  -> 从库主动脱离，Redis 8 下 replid 处理方式特殊，PSYNC 信息被清
#   2. DEBUG SLEEP       -> 从库恢复后直接追平，未触发重新同步（连接没断）
# 正确方法：在主库上 CLIENT KILL 掉从库的连接，模拟真实网络中断
BASE=/tmp/redis-course-l06-p4
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

gen 50000 base 20 | redis-cli -p $M --pipe > /dev/null 2>&1
redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
sleep 3
echo "=== 初始同步 ==="
echo "  从库 dbsize: $(redis-cli -p $S dbsize), link=$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')"
echo ""

echo "=== 查看主库上的从库连接 ==="
redis-cli -p $M client list | grep -i "cmd=replica\|cmd=psync\|flags=S" | head -2 | cut -c1-200
echo ""

run_case() {
  local label=$1 cnt=$2 sz=$3 backlog=$4

  redis-cli -p $M config set repl-backlog-size "$backlog" > /dev/null
  sleep 0.5
  # 确保同步正常
  local w=0
  while [ "$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')" != "up" ]; do
    sleep 0.5; w=$((w+1)); [ $w -gt 30 ] && break
  done

  : > "$BASE/s.log"; : > "$BASE/m.log"

  # 切断：在主库上 kill 掉从库的连接
  local addr=$(redis-cli -p $M client list | grep "flags=S" | grep -oP '(?<=addr=)[^ ]+' | head -1)
  if [ -n "$addr" ]; then
    redis-cli -p $M client kill "$addr" > /dev/null 2>&1
  fi
  sleep 0.5

  # 主库写入
  if [ "$cnt" -gt 0 ]; then
    gen $cnt gap $sz | redis-cli -p $M --pipe > /dev/null 2>&1
  fi

  sleep 5   # 等从库重连 + 可能的全量

  local verdict=""
  if grep -q "Successful partial resynchronization" "$BASE/s.log" 2>/dev/null; then
    verdict="✅ 增量复制 (partial resync 成功)"
  elif grep -qE "Unable to partial resync|Full resync requested|Full resync from master" "$BASE/m.log" "$BASE/s.log" 2>/dev/null; then
    verdict="❌ 全量复制 (backlog 覆盖不了)"
  else
    verdict="— 未触发重新同步"
  fi

  printf "  %-38s %s\n" "$label" "$verdict"
  echo "      从库 dbsize: $(redis-cli -p $S dbsize)  主库 dbsize: $(redis-cli -p $M dbsize)"
  grep -E "Successful partial|Unable to partial|Full resync|Connection with replica" "$BASE/s.log" "$BASE/m.log" 2>/dev/null | tail -1 | cut -c1-140 | sed 's/^/      /'
  echo ""
}

echo "########## CLIENT KILL 断线测试 ##########"
echo ""
run_case "A 写入 100 条×20B, backlog=1MB" 100 20 1mb
run_case "B 写入 5000 条×100B, backlog=1MB" 5000 100 1mb
run_case "C 写入 10 万条×200B, backlog=1MB" 100000 200 1mb
run_case "D 写入 10 万条×200B, backlog=64MB" 100000 200 64mb

echo "########## backlog 占用观测 ##########"
redis-cli -p $M info replication | grep -E "repl_backlog_size|repl_backlog_histlen"

echo ""
echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
