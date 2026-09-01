#!/usr/bin/env bash
# 课 6 知识点 1 深入：全量复制 vs 增量复制 触发条件与开销
BASE=/tmp/redis-course-l06-sync
rm -rf "$BASE"; mkdir -p "$BASE"/{m,s1}

start_master() {
  redis-server --port 6401 --daemonize yes --save '' --appendonly no \
    --dir "$BASE/m" --logfile "$BASE/m/redis.log" > /dev/null 2>&1
  sleep 1
}
start_slave() {
  local p=$1
  mkdir -p "$BASE/$p"
  redis-server --port "$p" --daemonize yes --save '' --appendonly no \
    --dir "$BASE/$p" --logfile "$BASE/$p/redis.log" > /dev/null 2>&1
  sleep 1
}

echo "########## 1. 全量复制完整流程观察 ##########"
start_master
start_slave 6402
# 灌 30 万 key
seq 1 300000 | awk '{print "set k:"$1" v"$1}' | redis-cli -p 6401 --pipe > /dev/null 2>&1
echo "  主库 dbsize: $(redis-cli -p 6401 dbsize)"
echo "  主库内存: $(redis-cli -p 6401 info memory | grep -oP '(?<=^used_memory:)\d+' | awk '{printf "%.1f MB", $1/1024/1024}')"

echo ""
echo "  --- 发起全量复制 ---"
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
# 高频观察同步状态
for i in $(seq 1 10); do
  ST=$(redis-cli -p 6402 info replication | grep -oP '(?<=^master_link_status:)\w+')
  DS=$(redis-cli -p 6402 dbsize)
  LB=$(redis-cli -p 6402 info replication | grep -oP '(?<=^master_sync_in_progress:)\d+')
  echo "    t=$(awk "BEGIN{printf \"%.1f\", $i*0.3}")s  link=$ST  dbsize=$DS  sync_in_progress=$LB"
  sleep 0.3
done
sleep 2
echo "  最终: $(redis-cli -p 6402 info replication | grep -oP '(?<=^master_link_status:)\w+'), dbsize=$(redis-cli -p 6402 dbsize)"

echo ""
echo "  --- 主库日志：全量复制的三个阶段 ---"
grep -E "Full resync|Background saving|DB saved on disk|Sending RDB|streaming the RDB|replica.*RDB|Done sending" "$BASE/m/redis.log" 2>/dev/null | tail -6 | cut -c1-160

echo ""
echo "  --- 从库日志：全量复制的三个阶段 ---"
grep -E "Full resync|Receiving|MASTER <-> REPLICA sync:|Flushing old data|Loading DB|Finished with success" "$BASE/6402/redis.log" 2>/dev/null | tail -8 | cut -c1-160

echo ""
echo "########## 2. 增量复制：断线重连后的 partial resync ##########"
echo "  当前主库 replid: $(redis-cli -p 6401 info replication | grep -oP '(?<=^master_replid:)\w+' | head -1)"
echo "  主库 backlog: $(redis-cli -p 6401 info replication | grep -E 'repl_backlog_active|repl_backlog_size|repl_backlog_histlen' | tr '\n' ' ')"

echo ""
echo "  --- 场景 A：短暂断网（backlog 能覆盖）---"
# 断开从库
redis-cli -p 6402 replicaof no one > /dev/null
sleep 0.5
# 主库写入少量数据
for i in $(seq 1 100); do redis-cli -p 6401 set "after:$i" "v$i" > /dev/null; done
OFF=$(redis-cli -p 6401 info replication | grep -oP '(?<=^master_repl_offset:)\d+')
echo "    断线期间主库写入 100 条, 主库 offset=$OFF"
# 重连
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
sleep 2
echo "    重连后从库 dbsize: $(redis-cli -p 6402 dbsize)"
echo "    sync_full 计数(从库): $(redis-cli -p 6402 info stats | grep -oP '(?<=^sync_full:)\d+')"
echo "    sync_partial_ok 计数(从库): $(redis-cli -p 6402 info stats | grep -oP '(?<=^sync_partial_ok:)\d+')"
grep -E "partial resynchronization|Trying a partial" "$BASE/6402/redis.log" | tail -2 | cut -c1-150

echo ""
echo "  --- 场景 B：长时间断网（backlog 覆盖不了，触发全量）---"
redis-cli -p 6402 replicaof no one > /dev/null
sleep 0.5
# 主库写入大量数据，撑爆 backlog
seq 1 200000 | awk '{print "set bulk:"$1" vvvvvvvvvvvvvvvvvvvv"$1}' | redis-cli -p 6401 --pipe > /dev/null 2>&1
echo "    断线期间主库写入 20 万条"
redis-cli -p 6402 replicaof 127.0.0.1 6401 > /dev/null
sleep 3
echo "    重连后 sync_full: $(redis-cli -p 6402 info stats | grep -oP '(?<=^sync_full:)\d+')"
echo "    重连后 sync_partial_ok: $(redis-cli -p 6402 info stats | grep -oP '(?<=^sync_partial_ok:)\d+')"
grep -E "Unable to partial|Full resync" "$BASE/6402/redis.log" | tail -2 | cut -c1-150

echo ""
echo "########## 3. repl_backlog_size 与容错窗口 ##########"
echo "  repl_backlog_size 默认: $(redis-cli -p 6401 config get repl-backlog-size | tail -1) 字节 = $(redis-cli -p 6401 config get repl-backlog-size | tail -1 | awk '{printf "%.0f MB", $1/1024/1024}')"
echo "  repl_backlog_ttl: $(redis-cli -p 6401 config get repl-backlog-ttl | tail -1) 秒"
echo "  client-output-buffer-limit slave: $(redis-cli -p 6401 config get client-output-buffer-limit | tail -1)"

echo ""
echo "########## 4. 无盘复制（diskless replication）##########"
echo "  repl-diskless-sync 默认: $(redis-cli -p 6401 config get repl-diskless-sync | tail -1)"
echo "  repl-diskless-sync-delay: $(redis-cli -p 6401 config get repl-diskless-sync-delay | tail -1) 秒"
echo "  repl-diskless-sync-max-replicas: $(redis-cli -p 6401 config get repl-diskless-sync-max-replicas | tail -1)"

echo ""
echo "########## 5. 复制风暴：多个从库同时全量 ##########"
echo "  同时挂 3 个从库，观察主库 fork 次数"
for p in 6403 6404 6405; do start_slave $p; done
F0=$(redis-cli -p 6401 info stats | grep -oP '(?<=^rdb_changes_since_last_save:)\d+')
for p in 6403 6404 6405; do redis-cli -p $p replicaof 127.0.0.1 6401 > /dev/null; done
sleep 4
echo "    主库 latest_fork_usec: $(redis-cli -p 6401 info stats | grep -oP '(?<=^latest_fork_usec:)\d+') us"
echo "    主库 sync_full 计数相关日志:"
grep -c "Starting BGSAVE for SYNC with target: replicas" "$BASE/m/redis.log" 2>/dev/null | awk '{print "      BGSAVE for SYNC 次数: " $1}'
grep -c "replicas waiting" "$BASE/m/redis.log" 2>/dev/null | awk '{print "      共享同一份 RDB 的次数: " $1}'

echo ""
echo "=== 清理 ==="
for p in 6405 6404 6403 6402 6401; do redis-cli -p $p shutdown nosave 2>/dev/null; done
sleep 1
rm -rf "$BASE"
echo "done"
