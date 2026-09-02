#!/bin/bash
# 结课实战项目 · 深挖复制失败根因
set -u

echo "===== 1. 从库 7202 最新日志 ====="
tail -20 /tmp/redis-final/7202/redis.log 2>/dev/null

echo
echo "===== 2. 主库 7201 视角：是否有从库连上来 ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' INFO replication 2>/dev/null | grep -E 'role|connected_slaves|slave0' | head -5

echo
echo "===== 3. 主库日志中来自从库的连接 ====="
grep -iE 'replica|slave|psync|noperm|denied' /tmp/redis-final/7201/redis.log 2>/dev/null | tail -10

echo
echo "===== 4. 手动测试 replicator 账号能否完成复制握手 ====="
echo -n "  replicator PING: "
redis-cli -p 7201 --user replicator --pass 'ReplPass123!' PING 2>/dev/null | head -1
echo -n "  replicator REPLCONF listening-port: "
redis-cli -p 7201 --user replicator --pass 'ReplPass123!' REPLCONF listening-port 7202 2>/dev/null | head -1
echo -n "  replicator REPLCONF capa: "
redis-cli -p 7201 --user replicator --pass 'ReplPass123!' REPLCONF capa eof capa psync2 2>/dev/null | head -1
echo -n "  replicator PSYNC ? -1: "
redis-cli -p 7201 --user replicator --pass 'ReplPass123!' PSYNC '?' -1 2>/dev/null | head -1

echo
echo "===== 5. 从库当前复制配置 ====="
redis-cli -p 7202 CONFIG GET masteruser 2>/dev/null | head -2
redis-cli -p 7202 CONFIG GET masterauth 2>/dev/null | head -2
redis-cli -p 7202 CONFIG GET replicaof 2>/dev/null | head -2
