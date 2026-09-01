#!/usr/bin/env bash
# 课 6 增量复制精确验证：partial resync 成功 vs 失败
# 修正：sync_full / sync_partial_ok 计数器要同时看主从；且要抓日志里的最终结论
BASE=/tmp/redis-course-l06-partial
rm -rf "$BASE"; mkdir -p "$BASE"

M=6401; S=6402

echo "=== 关键默认配置（Redis 8.10.1）==="
redis-server --port $M --daemonize yes --save '' --appendonly no --dir "$BASE" --logfile "$BASE/m.log" > /dev/null 2>&1
sleep 1
echo "  repl-diskless-sync: $(redis-cli -p $M config get repl-diskless-sync | tail -1)"
echo "  repl-backlog-size: $(redis-cli -p $M config get repl-backlog-size | tail -1) ($(redis-cli -p $M config get repl-backlog-size | tail -1 | awk '{printf "%.0f MB", $1/1024/1024}'))"
echo "  repl-backlog-ttl: $(redis-cli -p $M config get repl-backlog-ttl | tail -1) 秒"
echo ""

# 从库
mkdir -p "$BASE/s"
redis-server --port $S --daemonize yes --save '' --appendonly no --dir "$BASE/s" --logfile "$BASE/s.log" > /dev/null 2>&1
sleep 1

# 灌基础数据
seq 1 50000 | awk '{print "set base:"$1" v"$1}' | redis-cli -p $M --pipe > /dev/null 2>&1
echo "  主库基础数据: $(redis-cli -p $M dbsize) 个 key"
redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
sleep 3
echo "  首次同步完成，从库 dbsize: $(redis-cli -p $S dbsize)"
echo "  从库 sync_full=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_full:)\d+')  sync_partial_ok=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_partial_ok:)\d+')"
echo ""

echo "########## 精确验证：用日志判断 partial resync 成败 ##########"
echo ""

run_case() {
  local label=$1
  local write_cnt=$2
  local val_size=$3

  # 断开
  redis-cli -p $S replicaof no one > /dev/null
  sleep 1

  # 主库写入（用 --pipe 保证量足）
  if [ "$write_cnt" -gt 0 ]; then
    seq 1 $write_cnt | awk -v s=$val_size '{printf "set gap:%s %s\n", $1, sprintf("%*s", s, "")}' | redis-cli -p $M --pipe > /dev/null 2>&1
  fi

  local before_full=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_full:)\d+')
  local before_part=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_partial_ok:)\d+')

  # 清空日志便于抓本次结论
  : > "$BASE/s.log"

  # 重连
  redis-cli -p $S replicaof 127.0.0.1 $M > /dev/null
  sleep 3

  local after_full=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_full:)\d+')
  local after_part=$(redis-cli -p $S info stats | grep -oP '(?<=^sync_partial_ok:)\d+')

  # 抓日志结论
  local concl=$(grep -E "Successful partial resynchronization|Unable to partial resync|Full resync from master|Master replied to PING" "$BASE/s.log" | tail -1 | cut -c1-120)

  echo "  [$label] 写入 $write_cnt 条(每条约 ${val_size}B)"
  echo "    sync_full:      $before_full -> $after_full"
  echo "    sync_partial_ok: $before_part -> $after_part"
  echo "    日志结论: $concl"
  echo "    从库 dbsize: $(redis-cli -p $S dbsize)"
  echo ""
}

run_case "A 少量写入(100条/10B)" 100 10
run_case "B 中等写入(5000条/100B)" 5000 100
run_case "C 大量写入(10万条/200B)" 100000 200

echo "########## repl_backlog_histlen 变化 ##########"
redis-cli -p $M info replication | grep -E "repl_backlog_active|repl_backlog_size|repl_backlog_first_byte_offset|repl_backlog_histlen"
echo ""

echo "########## 关键：调大 backlog 后的效果 ##########"
redis-cli -p $M config set repl-backlog-size 64mb > /dev/null
sleep 0.5
echo "  调整后 repl-backlog-size: $(redis-cli -p $M config get repl-backlog-size | tail -1 | awk '{printf "%.0f MB", $1/1024/1024}')"
run_case "D 调大backlog后大量写入(10万条/200B)" 100000 200

echo ""
echo "=== 清理 ==="
redis-cli -p $S shutdown nosave 2>/dev/null
redis-cli -p $M shutdown nosave 2>/dev/null
sleep 1
rm -rf "$BASE"
echo "done"
