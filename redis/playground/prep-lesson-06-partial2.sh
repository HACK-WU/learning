#!/usr/bin/env bash
# 课 6 增量复制精确验证（修正版）
# 两个关键修正：
# 1. repl-diskless-sync-delay 默认 5 秒，等待必须 > 5s（之前所有测试失败的根因）
# 2. awk 的 sprintf("%*s",s,"") 产生非法命令，改用 python 生成
BASE=/tmp/redis-course-l06-p2
rm -rf "$BASE"; mkdir -p "$BASE"
M=6401; S=6402

redis-server --port $M --daemonize yes --save '' --appendonly no --dir "$BASE" --logfile "$BASE/m.log" > /dev/null 2>&1
mkdir -p "$BASE/s"
redis-server --port $S --daemonize yes --save '' --appendonly no --dir "$BASE/s" --logfile "$BASE/s.log" > /dev/null 2>&1
sleep 1

echo "=== Redis 8.10.1 关键默认（重点：diskless 相关）==="
echo "  repl-diskless-sync: $(redis-cli -p $M config get repl-diskless-sync | tail -1)"
echo "  repl-diskless-sync-delay: $(redis-cli -p $M config get repl-diskless-sync-delay | tail -1) 秒  <-- 等待攒从库"
echo "  repl-backlog-size: $(redis-cli -p $M config get repl-backlog-size | tail -1) bytes"
echo ""

gen() {  # $1=数量 $2=前缀 $3=值长度
python3 -c "
n=$1; pre='$2'; sz=$3
for i in range(1, n+1):
    val = 'v' * sz
    print('*3\r\n\$3\r\nSET\r\n\$%d\r\n%s:%d\r\n\$%d\r\n%s\r\n' % (len('%s:%d'%(pre,i)), pre, i, len(val), val))
"
}

# 基础数据
gen 50000 base 20 | redis-cli -p $M --pipe > /dev/null 2>&1
echo "  主库基础数据: $(redis-cli -p $M dbsize)"

echo ""
echo "=== 首次全量同步（等足 diskless delay）==="
redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
sleep 8   # 关键：必须 > 5 秒
echo "  从库 dbsize: $(redis-cli -p $S dbsize), link=$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')"
echo "  sync_full=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_full:)\d+')  sync_partial_ok=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_partial_ok:)\d+')"
echo ""

echo "########## partial resync 成败精确判定 ##########"
echo ""

run_case() {
  local label=$1 cnt=$2 sz=$3

  redis-cli -p $S replicaof no one > /dev/null
  sleep 1
  : > "$BASE/s.log"
  : > "$BASE/m.log"

  if [ "$cnt" -gt 0 ]; then
    gen $cnt gap $sz | redis-cli -p $M --pipe > /dev/null 2>&1
  fi

  local bf=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_full:)\d+')
  local bp=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_partial_ok:)\d+')

  redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
  sleep 8   # 等足 diskless delay

  local af=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_full:)\d+')
  local ap=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_partial_ok:)\d+')

  # 判定结论
  local verdict=""
  if grep -q "Successful partial resynchronization" "$BASE/s.log"; then
    verdict="✅ 增量复制（partial resync 成功）"
  elif grep -q "Unable to partial resync\|Full resync requested" "$BASE/m.log"; then
    verdict="❌ 全量复制（backlog 不够）"
  else
    verdict="(?待定)"
  fi

  printf "  %-32s sync_full %s->%s  sync_partial_ok %s->%s  %s\n" \
    "$label" "$bf" "$af" "$bp" "$ap" "$verdict"
  echo "      从库 dbsize: $(redis-cli -p $S dbsize)"
}

run_case "A 写入 100 条 × 20B" 100 20
run_case "B 写入 5000 条 × 100B" 5000 100
run_case "C 写入 10 万条 × 200B" 100000 200

echo ""
echo "########## 调大 backlog 后再测 ##########"
redis-cli -p $M config set repl-backlog-size 64mb > /dev/null
sleep 0.5
echo "  repl-backlog-size 现在: $(redis-cli -p $M config get repl-backlog-size | tail -1 | awk '{printf "%.0f MB", $1/1024/1024}')"
run_case "D 调大后写入 10 万条 × 200B" 100000 200

echo ""
echo "########## backlog 实际占用观测 ##########"
redis-cli -p $M info replication | grep -E "repl_backlog_active|repl_backlog_size|repl_backlog_histlen"

echo ""
echo "########## diskless delay 实测：把 delay 设为 0 ##########"
redis-cli -p $M config set repl-diskless-sync-delay 0 > /dev/null
redis-cli -p $S replicaof no one > /dev/null
sleep 1
: > "$BASE/m.log"
S_T=$(date +%s%N)
redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
for i in $(seq 1 20); do
  [ "$(redis-cli -p $S info replication | grep -oP '(?<=^master_link_status:)\w+')" = "up" ] && break
  sleep 0.2
done
E_T=$(date +%s%N)
echo "  delay=0 时同步完成耗时: $(awk "BEGIN{printf \"%.2f s\", ($E_T-$S_T)/1000000000}")"

echo ""
echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
