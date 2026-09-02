#!/bin/bash
# 复现验证后：查复制为什么还是 down
set -u
BASE=/tmp/redis-final

echo "===== 1. 从库 7202 复制状态 ====="
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'role|master_link_status|master_host|master_port|master_user' | head -6

echo
echo "===== 2. 从库日志尾部（真实原因） ====="
tail -8 $BASE/7202/redis.log 2>/dev/null

echo
echo "===== 3. 主库 7201 视角 ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' INFO replication 2>/dev/null | grep -E 'role|connected_slaves' | head -3

echo
echo "===== 4. 手动触发重连后复查 ====="
redis-cli -p 7202 REPLICAOF 127.0.0.1 7201 >/dev/null 2>&1
sleep 4
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'master_link_status|master_repl_offset|slave_repl_offset' | head -3

echo
echo "===== 5. 功能验证：主写从读 ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' SET cache:repl:check 'ok-from-master' >/dev/null 2>&1
sleep 1
echo -n "  从库读到: "
redis-cli -p 7202 GET cache:repl:check 2>/dev/null | head -1
