#!/usr/bin/env bash
# 课 5 补充：延迟分布 + 重启加载优先级实测
PORT=6405
BASE=/tmp/redis-course-l05-lat
rm -rf "$BASE"; mkdir -p "$BASE/d"

echo "########## 1. 延迟分布（修正 grep 格式）##########"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$BASE/d" --maxmemory 0 > /dev/null 2>&1
sleep 1.5

for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  sleep 1
  echo "--- appendfsync=$pol ---"
  redis-benchmark -p "$PORT" -n 30000 -c 10 -t set 2>/dev/null | grep -E "^(50|95|99|99.9)%|<=" | head -4
  echo ""
done

redis-cli -p "$PORT" config set appendfsync everysec > /dev/null

echo "########## 2. 重启加载：AOF 与 RDB 谁优先 ##########"
echo "场景：同时存在 dump.rdb 和 appendonlydir，且两者数据不同"
echo ""

redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" set only:in:aof "I-am-in-AOF" > /dev/null
redis-cli -p "$PORT" bgsave > /dev/null   # 生成 RDB，此刻 RDB 也含 only:in:aof
sleep 2
# 再写一条只进 AOF 的新数据（不 bgsave）
redis-cli -p "$PORT" set only:in:aof2 "I-am-AOF-only" > /dev/null
sleep 1.2

echo "  RDB 文件存在: $([ -f "$BASE/d/dump.rdb" ] && echo yes || echo no)"
echo "  AOF 目录存在: $([ -d "$BASE/d/appendonlydir" ] && echo yes || echo no)"
echo "  关闭前 dbsize: $(redis-cli -p "$PORT" dbsize)"

# 正常关闭（会 fsync AOF）
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 1.5

redis-server --port "$PORT" --daemonize yes --dir "$BASE/d" > /dev/null 2>&1
sleep 2
echo "  重启后 dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  only:in:aof  = $(redis-cli -p "$PORT" get only:in:aof)"
echo "  only:in:aof2 = $(redis-cli -p "$PORT" get only:in:aof2)  <-- 只有 AOF 有的数据"
echo "  结论: $([ "$(redis-cli -p "$PORT" get only:in:aof2)" = "I-am-AOF-only" ] && echo 'AOF 优先（数据更完整）' || echo 'RDB 优先')"

echo ""
echo "########## 3. 断电模拟：kill -9 后丢多少数据 ##########"
redis-cli -p "$PORT" config set appendfsync everysec > /dev/null

for pol in no everysec always; do
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  redis-cli -p "$PORT" flushall > /dev/null
  sleep 0.5

  # 写入 2000 条
  for i in $(seq 1 2000); do echo "set kill:test:$i v$i"; done | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  CNT_BEFORE=$(redis-cli -p "$PORT" dbsize)

  # 立即 kill -9（不给 fsync 机会）
  PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
  kill -9 "$PID" 2>/dev/null
  sleep 1.5

  # 重启
  rm -f "$BASE/d/dump.rdb"
  redis-server --port "$PORT" --daemonize yes --dir "$BASE/d" > /dev/null 2>&1
  sleep 2.5
  CNT_AFTER=$(redis-cli -p "$PORT" dbsize 2>/dev/null || echo 0)

  echo "  appendfsync=$pol: 写入 $CNT_BEFORE 条 -> 重启后剩 $CNT_AFTER 条 (丢失 $((CNT_BEFORE - CNT_AFTER)) 条)"
  redis-cli -p "$PORT" flushall > /dev/null 2>&1
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
rm -rf "$BASE"
echo "done"
