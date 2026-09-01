#!/usr/bin/env bash
# 课 5 重启加载与断电丢数据（修正版）
# 前面失败原因：重启时没加 --appendonly yes，AOF 根本没被加载
# 修正：重启必须显式带上与关闭时相同的持久化配置
PORT=6405
BASE=/tmp/redis-course-l05-restart
rm -rf "$BASE"; mkdir -p "$BASE/d"

echo "########## 1. AOF 与 RDB 同时存在时，谁优先？##########"
# 启动时就开启 appendonly
redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$BASE/d" --maxmemory 0 > /dev/null 2>&1
sleep 1.5

redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" set shared:key "in-both" > /dev/null
redis-cli -p "$PORT" bgsave > /dev/null
sleep 2
# 这条只进 AOF（不再 bgsave）
redis-cli -p "$PORT" set aof:only "I-am-AOF-only" > /dev/null
sleep 1.2

echo "  dump.rdb 存在: $([ -f "$BASE/d/dump.rdb" ] && echo yes || echo no)"
echo "  appendonlydir 存在: $([ -d "$BASE/d/appendonlydir" ] && echo yes || echo no)"
echo "  关闭前 dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  aof_enabled: $(redis-cli -p "$PORT" info persistence | grep -oP '(?<=^aof_enabled:)\d+')"

# 正常关闭：用 shutdown（默认会保存），确保 AOF 刷盘
redis-cli -p "$PORT" shutdown 2>/dev/null
sleep 2

# 重启：必须带 --appendonly yes
redis-server --port "$PORT" --daemonize yes --appendonly yes --dir "$BASE/d" > /dev/null 2>&1
sleep 2.5
echo "  重启后 dbsize: $(redis-cli -p "$PORT" dbsize)"
echo "  shared:key = $(redis-cli -p "$PORT" get shared:key)"
echo "  aof:only  = $(redis-cli -p "$PORT" get aof:only)"
if [ "$(redis-cli -p "$PORT" get aof:only)" = "I-am-AOF-only" ]; then
  echo "  结论: ✅ AOF 优先（含 RDB 没有的数据）"
else
  echo "  结论: RDB 优先"
fi
echo "  加载来源: $(redis-cli -p "$PORT" info persistence | grep -E 'aof_enabled|loading' | tr '\n' ' ')"

echo ""
echo "########## 2. 断电模拟：kill -9 后各策略丢多少 ##########"
echo "说明：kill -9 不给 Redis 任何 fsync 机会，最贴近真实宕机"
echo ""

for pol in no everysec always; do
  # 每个策略用独立目录，避免相互污染
  D="$BASE/kill-$pol"; mkdir -p "$D"
  redis-cli -p "$PORT" shutdown nosave 2>/dev/null
  sleep 1
  redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$D" --maxmemory 0 > /dev/null 2>&1
  sleep 1.5
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  redis-cli -p "$PORT" flushall > /dev/null
  sleep 0.5

  N=2000
  for i in $(seq 1 $N); do echo "set k:$i v$i"; done | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  CNT_BEFORE=$(redis-cli -p "$PORT" dbsize)

  # always 策略下，命令返回即已落盘；everysec/no 需要额外等待才落盘
  if [ "$pol" = "everysec" ]; then sleep 1.2; fi
  if [ "$pol" = "no" ]; then sleep 1.2; fi

  PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
  kill -9 "$PID" 2>/dev/null
  sleep 1.5

  redis-server --port "$PORT" --daemonize yes --appendonly yes --dir "$D" > /dev/null 2>&1
  sleep 2.5
  CNT_AFTER=$(redis-cli -p "$PORT" dbsize 2>/dev/null || echo 0)
  [ -z "$CNT_AFTER" ] && CNT_AFTER=0

  echo "  appendfsync=$pol: 写入 $CNT_BEFORE -> 恢复 $CNT_AFTER (丢失 $((CNT_BEFORE - CNT_AFTER)) 条)"
done

echo ""
echo "########## 3. 极端对照：立即 kill（不给 1.2 秒等待）##########"
for pol in everysec always; do
  D="$BASE/fast-$pol"; mkdir -p "$D"
  redis-cli -p "$PORT" shutdown nosave 2>/dev/null
  sleep 1
  redis-server --port "$PORT" --daemonize yes --save '' --appendonly yes --dir "$D" --maxmemory 0 > /dev/null 2>&1
  sleep 1.5
  redis-cli -p "$PORT" config set appendfsync "$pol" > /dev/null
  redis-cli -p "$PORT" flushall > /dev/null
  sleep 0.5
  for i in $(seq 1 2000); do echo "set k:$i v$i"; done | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  CB=$(redis-cli -p "$PORT" dbsize)
  PID=$(redis-cli -p "$PORT" info server | grep -oP '(?<=^process_id:)\d+')
  kill -9 "$PID" 2>/dev/null   # 写入后立刻杀，不等
  sleep 1.5
  redis-server --port "$PORT" --daemonize yes --appendonly yes --dir "$D" > /dev/null 2>&1
  sleep 2.5
  CA=$(redis-cli -p "$PORT" dbsize 2>/dev/null || echo 0)
  [ -z "$CA" ] && CA=0
  echo "  appendfsync=$pol (立即kill): 写入 $CB -> 恢复 $CA (丢失 $((CB - CA)) 条)"
done

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
rm -rf "$BASE"
echo "done"
