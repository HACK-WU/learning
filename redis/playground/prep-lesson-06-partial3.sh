#!/usr/bin/env bash
# 课 6 增量复制终极验证：用网络中断（而非 replicaof no one）制造断线
# 关键修正：replicaof no one 会更换 replid，导致 PSYNC 必然失败 -> 永远走全量
# 正确方法：保持从库的 replicaof 配置不变，只切断网络（或用 DEBUG SLEEP 阻塞从库）
BASE=/tmp/redis-course-l06-p3
rm -rf "$BASE"; mkdir -p "$BASE"
M=6401; S=6402

redis-server --port $M --daemonize yes --save '' --appendonly no --dir "$BASE" --logfile "$BASE/m.log" > /dev/null 2>&1
mkdir -p "$BASE/s"
redis-server --port $S --daemonize yes --save '' --appendonly no --dir "$BASE/s" --logfile "$BASE/s.log" > /dev/null 2>&1
sleep 1

gen() {
python3 -c "
n=$1; pre='$2'; sz=$3
for i in range(1, n+1):
    val = 'v' * sz
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\n%s:%d\r\n\$%d\r\n%s\r\n' % (len('%s:%d'%(pre,i)), pre, i, len(val), val))
"
}

echo "=== 前置认知：replicaof no one 会换 replid ==="
echo "  主库 replid: $(redis-cli -p $M info replication | grep -oP '(?<=^master_replid:)\w+' | head -1)"
R1=$(redis-cli -p $M info replication | grep -oP '(?<=^master_replid:)\w+' | head -1)
redis-cli -p $M replicaof no one > /dev/null 2>&1
sleep 1
R2=$(redis-cli -p $M info replication | grep -oP '(?<=^master_replid:)\w+' | head -1)
echo "  执行 replicaof no one 后 replid: $R2"
if [ "$R1" != "$R2" ]; then
  echo "  ✅ 确认：replid 已改变 -> PSYNC 必然失败，只能全量"
else
  echo "  replid 未变"
fi
echo ""

echo "=== 建立主从（diskless delay 设 0 加速）==="
redis-cli -p $M config set repl-diskless-sync-delay 0 > /dev/null
gen 50000 base 20 | redis-cli -p $M --pipe > /dev/null 2>&1
redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
sleep 3
echo "  从库 dbsize: $(redis-cli -p $S dbsize), link=$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')"
echo ""

echo "########## 用 DEBUG SLEEP 阻塞从库来模拟网络中断 ##########"
echo "  原理：从库主线程被阻塞 -> 无法处理主库发来的命令流"
echo "        但从库的 replicaof 配置和 replid 保持不变"
echo ""

run_case() {
  local label=$1 cnt=$2 sz=$3 backlog=$4

  # 设置 backlog
  redis-cli -p $M config set repl-backlog-size "$backlog" > /dev/null
  sleep 0.3

  # 确保同步状态正常
  local w=0
  while [ "$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')" != "up" ]; do
    sleep 0.5; w=$((w+1)); [ $w -gt 20 ] && break
  done

  : > "$BASE/s.log"
  : > "$BASE/m.log"

  # 阻塞从库（后台执行，不阻塞本脚本）
  ( redis-cli -p $S debug sleep 3 > /dev/null 2>&1 ) &
  sleep 0.3

  # 主库写入
  if [ "$cnt" -gt 0 ]; then
    gen $cnt gap $sz | redis-cli -p $M --pipe > /dev/null 2>&1
  fi

  # 等待从库恢复
  wait 2>/dev/null
  sleep 4

  # 判定
  local verdict=""
  if grep -q "Successful partial resynchronization" "$BASE/s.log" 2>/dev/null; then
    verdict="✅ 增量复制 (partial resync)"
  elif grep -qE "Unable to partial resync|Full resync requested" "$BASE/m.log" 2>/dev/null; then
    verdict="❌ 全量复制 (full resync)"
  else
    verdict="— 未断线（同步未中断）"
  fi

  printf "  %-34s %s\n" "$label" "$verdict"
  echo "      从库 dbsize: $(redis-cli -p $S dbsize)"
  # 打印关键日志行
  grep -E "Successful partial|Unable to partial|Full resync" "$BASE/s.log" "$BASE/m.log" 2>/dev/null | tail -1 | cut -c1-130 | sed 's/^/      /'
}

run_case "A 少量写入(100条×20B) backlog=1MB" 100 20 1mb
run_case "B 中等写入(5000条×100B) backlog=1MB" 5000 100 1mb
run_case "C 大量写入(10万条×200B) backlog=1MB" 100000 200 1mb
run_case "D 大量写入(10万条×200B) backlog=64MB" 100000 200 64mb

echo ""
echo "########## 结论验证：backlog 大小决定增量能否成功 ##########"
echo ""

echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
