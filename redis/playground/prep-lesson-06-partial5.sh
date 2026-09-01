#!/usr/bin/env bash
# 课 6 增量复制边界测试：找到 backlog 覆盖不了的临界点
# 修正：断线时间太短，从库在被 kill 后就立刻重连，主库写入还没撑爆 backlog
# 方法：kill 后持续写入更久（让 backlog 真的被覆盖），再让从库重连
BASE=/tmp/redis-course-l06-p5
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
echo "  初始: 从库 dbsize=$(redis-cli -p $S dbsize) link=$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')"
echo ""

run_case() {
  local label=$1 backlog=$2 write_mb=$3

  redis-cli -p $M config set repl-backlog-size "$backlog" > /dev/null
  sleep 0.5
  local w=0
  while [ "$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')" != "up" ]; do
    sleep 0.5; w=$((w+1)); [ $w -gt 30 ] && break
  done

  : > "$BASE/s.log"; : > "$BASE/m.log"

  # 关键：先 kill 连接，然后持续写入足够多的数据撑爆 backlog
  local addr=$(redis-cli -p $M client list | grep "flags=S" | grep -oP '(?<=addr=)[^ ]+' | head -1)
  [ -n "$addr" ] && redis-cli -p $M client kill "$addr" > /dev/null 2>&1

  # 持续写入 write_mb MB（分批，每批后检查是否已重连）
  local batches=$(( write_mb * 10 ))   # 每批约 0.1MB
  local reconnected=0
  for b in $(seq 1 $batches); do
    gen 500 gap 200 | redis-cli -p $M --pipe > /dev/null 2>&1
    # 检查是否已自动重连
    if [ "$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')" = "up" ]; then
      reconnected=1
      break
    fi
  done

  sleep 5

  local verdict=""
  if grep -q "Successful partial resynchronization" "$BASE/s.log" 2>/dev/null; then
    verdict="✅ 增量 (partial resync)"
  elif grep -qE "Unable to partial resync|Full resync requested|Full resync from master" "$BASE/m.log" "$BASE/s.log" 2>/dev/null; then
    verdict="❌ 全量 (backlog 不够)"
  else
    verdict="— 未重连"
  fi

  printf "  %-40s %s  (自动重连=%s)\n" "$label" "$verdict" "$reconnected"
  echo "      从库 dbsize=$(redis-cli -p $S dbsize)  主库 dbsize=$(redis-cli -p $M dbsize)"
  grep -hE "Successful partial|Unable to partial|Full resync" "$BASE/s.log" "$BASE/m.log" 2>/dev/null | tail -1 | cut -c1-135 | sed 's/^/      /'
  echo ""
}

echo "########## 边界测试：backlog=1MB (默认) ##########"
echo ""
run_case "backlog=1MB, 断线期间写 ~0.5MB" 1mb 1
run_case "backlog=1MB, 断线期间写 ~2MB" 1mb 4
run_case "backlog=1MB, 断线期间写 ~10MB" 1mb 20

echo "########## 边界测试：backlog=64MB ##########"
echo ""
run_case "backlog=64MB, 断线期间写 ~10MB" 64mb 20

echo "########## backlog 占用 ##########"
redis-cli -p $M info replication | grep -E "repl_backlog_size|repl_backlog_histlen"

echo ""
echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
