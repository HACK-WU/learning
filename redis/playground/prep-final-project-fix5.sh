#!/bin/bash
# 结课实战项目 · 复制健康度与延迟实测
set -u

echo "===== 1. 复制链路最终状态 ====="
redis-cli -p 7202 INFO replication 2>/dev/null | grep -E 'role|master_link_status|master_repl_offset|slave_repl_offset|master_last_io_seconds_ago' | head -6

echo
echo "===== 2. 主库视角：已连接的从库 ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' INFO replication 2>/dev/null | grep -E 'role|connected_slaves|slave0:|offset' | head -5

echo
echo "===== 3. 主从同步功能验证 ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' SET cache:sync-final 'v-final' >/dev/null 2>&1
sleep 1
echo -n "  从库读到 cache:sync-final = "
redis-cli -p 7202 GET cache:sync-final 2>/dev/null | head -1

echo
echo "===== 4. 复制延迟实测（写主读从，看多久能看到） ====="
# 用自增 key 制造连续写入，同时轮询从库，测量可见延迟
redis-cli -p 7201 --user appuser --pass 'AppPass123!' SET cache:latency:0 v0 >/dev/null 2>&1
for i in $(seq 1 20); do
  redis-cli -p 7201 --user appuser --pass 'AppPass123!' SET cache:latency:$i v$i >/dev/null 2>&1
done
echo "  已写入 21 个 key，立即查从库："
echo -n "    从库 cache:latency:20 = "
redis-cli -p 7202 GET cache:latency:20 2>/dev/null | head -1
echo -n "    从库当前 keys 数 = "
redis-cli -p 7202 DBSIZE 2>/dev/null | head -1
echo -n "    主库当前 keys 数 = "
redis-cli -p 7201 --user appuser --pass 'AppPass123!' DBSIZE 2>/dev/null | head -1

echo
echo "===== 5. 从库只读性验证（阶段3·课6 知识点） ====="
echo -n "  从库执行 SET（应报 READONLY 错）: "
redis-cli -p 7202 SET cache:write-to-replica 1 2>&1 | head -1

echo
echo "===== 6. 复制积压缓冲区（增量复制基础） ====="
redis-cli -p 7201 --user appuser --pass 'AppPass123!' INFO replication 2>/dev/null | grep -E 'repl_backlog_size|repl_backlog_active' | head -2
