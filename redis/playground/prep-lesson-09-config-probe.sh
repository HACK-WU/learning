#!/bin/bash
# 课 9 备课：核对性能诊断相关默认值与命令可用性
R="redis-cli -p 6379"

echo "=== 1. slowlog 相关默认值 ==="
$R config get slowlog-log-slower-than
$R config get slowlog-max-len
$R config get latency-monitor-threshold

echo ""
echo "=== 2. 内存相关默认值 ==="
$R config get maxmemory
$R config get maxmemory-policy
$R config get maxmemory-samples
$R config get maxmemory-eviction-tenacity

echo ""
echo "=== 3. io-threads 默认 ==="
$R config get io-threads
$R config get io-threads-do-reads

echo ""
echo "=== 4. 客户端/连接 ==="
$R config get maxclients
$R config get timeout
$R config get tcp-keepalive

echo ""
echo "=== 5. 安全相关默认 ==="
$R config get requirepass
$R config get protected-mode
$R config get bind
$R acl list 2>&1 | head -5
echo "--- rename-command ---"
$R config get rename-command 2>&1 | head -5

echo ""
echo "=== 6. 危险命令是否被禁用/重命名 ==="
for c in FLUSHALL FLUSHDB KEYS CONFIG SHUTDOWN DEBUG; do
  out=$($R $c 2>&1 | head -1)
  echo "  $c -> $out"
done

echo ""
echo "=== 7. 命令可用性探测（诊断类） ==="
for c in "SLOWLOG GET" "MEMORY USAGE" "MEMORY STATS" "MEMORY DOCTOR" "LATENCY DOCTOR" "LATENCY LATEST" "OBJECT FREQ" "OBJECT IDLETIME" "INFO commandstats" "CLIENT LIST"; do
  out=$($R $c 2>&1 | head -1)
  echo "  $c -> ${out:0:80}"
done

echo ""
echo "=== 8. --bigkeys / --memkeys / --hotkeys 支持 ==="
redis-cli --help 2>&1 | grep -iE "bigkeys|memkeys|hotkeys|latency|stat|scan|intrinsic" 

echo ""
echo "=== 9. INFO 关键段是否存在 ==="
for s in commandstats latency mem_fragmentation_ratio instantaneous_ops_per_sec; do
  echo "  $s -> $($R info 2>/dev/null | grep -c "$s")"
done

echo ""
echo "=== 10. 数据库数量 / 现有 key ==="
$R config get databases
$R dbsize
