#!/usr/bin/env bash
# 课 5 丢数据窗口精确测量：写入后立刻 kill，用更细的时间切片
# WSL 环境下 --pipe 后紧接 kill 仍不丢，需要更精细的方法：
# 用单客户端持续写入 + 在写入过程中随机时刻 kill
PORT=6405
BASE=/tmp/redis-course-l05-loss
rm -rf "$BASE"

echo "########## 方法：持续写入，在写入过程中 kill ##########"
echo ""

for pol in no everysec always; do
  D="$BASE/$pol"; mkdir -p "$D"
  redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$D" --maxmemory 0 > /dev/null 2>&1
  sleep 1.5
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  redis-cli -p "$PORT" flushall > /dev/null
  sleep 0.5

  # 后台持续写入（记录已确认写入的条数）
  rm -f "$BASE/written.txt"
  ( for i in $(seq 1 6000); do
      redis-cli -p "$PORT" set "key:$i" "v$i" > /dev/null 2>&1
      echo "$i" > "$BASE/written.txt"
    done ) &
  WPID=$!

  # 写入进行到中途时 kill
  sleep 2.5
  PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
  kill -9 "$PID" 2>/dev/null
  WRITTEN=$(cat "$BASE/written.txt" 2>/dev/null || echo 0)
  kill $WPID 2>/dev/null
  wait $WPID 2>/dev/null
  sleep 1.5

  redis-server --port "$PORT" --daemonize yes --appendonly yes --dir "$D" > /dev/null 2>&1
  sleep 2.5
  AFTER=$(redis-cli -p "$PORT" dbsize 2>/dev/null || echo 0)
  [ -z "$AFTER" ] && AFTER=0
  [ -z "$WRITTEN" ] && WRITTEN=0

  LOST=$((WRITTEN - AFTER))
  [ "$LOST" -lt 0 ] && LOST=0
  echo "  appendfsync=$pol:"
  echo "    已确认写入: $WRITTEN 条"
  echo "    重启后恢复: $AFTER 条"
  echo "    丢失: $LOST 条"
  redis-cli -p "$PORT" shutdown nosave 2>/dev/null
  sleep 1
done

echo ""
echo "########## 补充：用 INFO 观察 fsync 状态 ##########"
D="$BASE/info"; mkdir -p "$D"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$D" --maxmemory 0 > /dev/null 2>&1
sleep 1.5
for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  redis-cli -p "$PORT" flushall > /dev/null
  for i in $(seq 1 3000); do echo "set a:$i b$i"; done | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  sleep 0.2
  echo "  --- appendfsync=$pol ---"
  redis-cli -p "$PORT" info persistence | grep -E "aof_pending_bio_fsync|aof_buffer_length|aof_last_write_status|aof_rewrite_in_progress" | sed 's/^/    /'
  echo "    AOF 文件大小: $(du -sb "$D/appendonlydir" | awk '{print $1}') 字节"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
rm -rf "$BASE"
echo "done"
