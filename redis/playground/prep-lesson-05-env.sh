#!/usr/bin/env bash
# 课 5 备课：持久化配置基线核对
PORT=6405
DIR=/tmp/redis-course-l05
mkdir -p "$DIR"

echo "=== 版本 ==="
redis-server --version
echo ""

redis-server --port "$PORT" --daemonize yes --dir "$DIR" > /dev/null 2>&1
sleep 1
echo "PING: $(redis-cli -p "$PORT" ping)"
echo ""

echo "=== RDB 相关默认配置 ==="
redis-cli -p "$PORT" config get save
echo "---"
redis-cli -p "$PORT" config get dbfilename
redis-cli -p "$PORT" config get dir
redis-cli -p "$PORT" config get rdbcompression
redis-cli -p "$PORT" config get rdbchecksum
echo ""

echo "=== AOF 相关默认配置 ==="
redis-cli -p "$PORT" config get appendonly
redis-cli -p "$PORT" config get appendfilename
redis-cli -p "$PORT" config get appendfsync
redis-cli -p "$PORT" config get appenddirname
echo ""

echo "=== Redis 7+ AOF multi-part 结构 ==="
redis-cli -p "$PORT" config get aof-use-rdb-preamble
echo ""

echo "=== 后台线程 / fsync 相关 ==="
redis-cli -p "$PORT" config get io-threads
redis-cli -p "$PORT" config get io-threads-do-reads
echo ""

echo "=== 相关：fork 与内存 ==="
echo "maxmemory: $(redis-cli -p "$PORT" config get maxmemory | tail -1)"
echo "当前 used_memory: $(redis-cli -p "$PORT" info memory | grep -oP '(?<=^used_memory:)\d+')"
echo ""

echo "=== 内核 overcommit 设置（影响 fork 成功率）==="
cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "  (读取失败)"
echo "  overcommit_memory=0 启发式 / 1 总是允许 / 2 严格"
echo ""

echo "=== THP 设置（影响 fork 后 COW 放大）==="
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
  echo "  $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
else
  echo "  (文件不存在)"
fi
echo ""

echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
sleep 0.5
rmdir "$DIR" 2>/dev/null
echo "done"
