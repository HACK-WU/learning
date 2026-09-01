#!/bin/bash
# 课 9 备课：默认值核对（严格只读 —— 绝不执行任何写/破坏性命令）
R="redis-cli -p 6379"

echo "=== 0. 连通性与身份 ==="
$R ping
$R info server | grep -E "redis_version|executable|config_file|run_id|uptime_in_seconds"

echo ""
echo "=== 1. io-threads 完整 ==="
$R config get io-threads
$R config get io-threads-do-reads
echo "--- CPU 核数 ---"
nproc

echo ""
echo "=== 2. 安全：ACL 现状（只列，不改） ==="
$R acl list
$R acl whoami
echo "--- ACL 相关配置 ---"
$R config get aclfile
$R config get acl-pubsub-default
$R config get enable-debug-command
$R config get enable-module-command
$R config get enable-protected-configs

echo ""
echo "=== 3. 危险命令：只检查是否被重命名/ACL 限制，不执行 ==="
echo "  (default user 权限串见上方 acl list，+@all 表示无限制)"

echo ""
echo "=== 4. 诊断命令可用性（只读类） ==="
echo "--- SLOWLOG GET (前 2 条) ---"
$R slowlog get 2
echo "--- SLOWLOG LEN ---"
$R slowlog len
echo "--- LATENCY LATEST ---"
$R latency latest 2>&1 | head -5
echo "--- LATENCY DOCTOR ---"
$R latency doctor 2>&1 | head -20
echo "--- MEMORY DOCTOR ---"
$R memory doctor 2>&1 | head -20

echo ""
echo "=== 5. INFO 关键字段实测 ==="
$R info stats | grep -E "instantaneous_ops_per_sec|total_commands_processed|keyspace_hits|keyspace_misses|latest_fork_usec|rejected_connections|expired_keys|evicted_keys"
echo "--- memory ---"
$R info memory | grep -E "used_memory_human|used_memory_peak_human|mem_fragmentation_ratio|maxmemory_policy|maxmemory_human"
echo "--- clients ---"
$R info clients | grep -E "connected_clients|blocked_clients|client_recent_max_input_buffer"
echo "--- commandstats 是否存在（需 INFO 全量） ---"
$R info commandstats 2>&1 | head -8

echo ""
echo "=== 6. 数据库 ==="
$R config get databases
$R dbsize
$R info keyspace

echo ""
echo "=== 7. OBJECT 命令可用性 ==="
$R set probe:k hello >/dev/null
$R object encoding probe:k
$R object refcount probe:k
$R object idletime probe:k
$R memory usage probe:k
$R del probe:k >/dev/null
echo "  (探测 key 已删除)"

echo ""
echo "=== 8. OBJECT FREQ（需 lfu 策略） ==="
$R config get maxmemory-policy
$R object freq probe:k 2>&1 | head -2

echo ""
echo "=== 9. 持久化现状 ==="
$R config get appendonly
$R config get save
$R info persistence | grep -E "rdb_last_bgsave_status|aof_enabled|rdb_changes_since_last_save"

echo ""
echo "=== 10. 集群模式 ==="
$R info cluster 2>/dev/null | head -3
$R cluster info 2>&1 | head -3
