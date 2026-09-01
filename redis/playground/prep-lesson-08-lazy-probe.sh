#!/usr/bin/env bash
# 探测：能否关闭定期删除，从而单独验证惰性删除
set -u
PORT=7103
mkdir -p /tmp/redis-l08
redis-cli -p $PORT shutdown nosave 2>/dev/null; sleep 0.3
redis-server --port $PORT --save '' --appendonly no --dir /tmp/redis-l08 \
  --dbfilename l08d.rdb --daemonize yes --logfile /tmp/redis-l08/$PORT.log
for i in $(seq 1 50); do redis-cli -p $PORT ping >/dev/null 2>&1 && break; sleep 0.1; done
echo "===== PING ====="
redis-cli -p $PORT ping
echo "===== DEBUG SET-ACTIVE-EXPIRE 0（关闭定期删除）====="
redis-cli -p $PORT DEBUG SET-ACTIVE-EXPIRE 0 2>&1 | head -3
echo "===== 写入 TTL=2 的 key ====="
redis-cli -p $PORT SET lazy:k v EX 2
echo "===== 等 3 秒后看是否还在（定期删除已关闭）====="
sleep 3
echo "DBSIZE: $(redis-cli -p $PORT DBSIZE)"
echo "GET lazy:k: $(redis-cli -p $PORT GET lazy:k)"
echo "EXISTS: $(redis-cli -p $PORT EXISTS lazy:k)"
echo "expired_keys: $(redis-cli -p $PORT INFO stats | grep expired_keys)"
echo "===== 主动访问一次后再看 ====="
redis-cli -p $PORT GET lazy:k
echo "DBSIZE after access: $(redis-cli -p $PORT DBSIZE)"
echo "expired_keys after access: $(redis-cli -p $PORT INFO stats | grep expired_keys)"
echo "===== 恢复定期删除 ====="
redis-cli -p $PORT DEBUG SET-ACTIVE-EXPIRE 1 2>&1 | head -3
echo "===== OBJECT IDLETIME 探测（LRU 时钟，maxmemory-policy 需非 LFU）====="
redis-cli -p $PORT CONFIG SET maxmemory-policy allkeys-lru
redis-cli -p $PORT SET idle:a 1
redis-cli -p $PORT SET idle:b 1
sleep 1
redis-cli -p $PORT GET idle:a
echo "idle:a IDLETIME（刚访问）: $(redis-cli -p $PORT OBJECT IDLETIME idle:a)"
echo "idle:b IDLETIME（未访问）: $(redis-cli -p $PORT OBJECT IDLETIME idle:b)"
echo "===== OBJECT FREQ 探测（LFU 计数器）====="
redis-cli -p $PORT CONFIG SET maxmemory-policy allkeys-lfu
redis-cli -p $PORT SET freq:a 1
redis-cli -p $PORT SET freq:b 1
for i in $(seq 1 30); do redis-cli -p $PORT GET freq:a >/dev/null; done
echo "freq:a FREQ（访问30次）: $(redis-cli -p $PORT OBJECT FREQ freq:a)"
echo "freq:b FREQ（未访问）  : $(redis-cli -p $PORT OBJECT FREQ freq:b)"
echo "===== LFU 相关配置 ====="
redis-cli -p $PORT CONFIG GET lfu-log-factor
redis-cli -p $PORT CONFIG GET lfu-decay-time
echo "===== MEMORY USAGE 单个 key ====="
redis-cli -p $PORT MEMORY USAGE freq:a
echo "===== 清理 ====="
redis-cli -p $PORT flushall
redis-cli -p $PORT shutdown nosave 2>/dev/null
echo "done"
