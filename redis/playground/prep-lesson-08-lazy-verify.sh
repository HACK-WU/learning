#!/usr/bin/env bash
# 用 enable-debug-command local 放开 DEBUG，隔离验证惰性删除
set -u
PORT=7103
mkdir -p /tmp/redis-l08
redis-cli -p $PORT shutdown nosave 2>/dev/null; sleep 0.3
redis-server --port $PORT --save '' --appendonly no --dir /tmp/redis-l08 \
  --dbfilename l08d.rdb --daemonize yes --logfile /tmp/redis-l08/$PORT.log \
  --enable-debug-command local
for i in $(seq 1 50); do redis-cli -p $PORT ping >/dev/null 2>&1 && break; sleep 0.1; done
echo "===== PING: $(redis-cli -p $PORT ping) ====="
echo "===== DEBUG SET-ACTIVE-EXPIRE 0 ====="
redis-cli -p $PORT DEBUG SET-ACTIVE-EXPIRE 0 2>&1 | head -2
echo "===== 写入 3 个 TTL=2s 的 key ====="
for k in lazy:a lazy:b lazy:c; do redis-cli -p $PORT SET $k v EX 2 >/dev/null; done
echo "写入后 DBSIZE: $(redis-cli -p $PORT DBSIZE)"
echo "===== 等 3.5 秒（key 已过期，但定期删除已关闭）====="
sleep 3.5
echo "DBSIZE（应仍为 3，因为定期删除被关了）: $(redis-cli -p $PORT DBSIZE)"
echo "EXISTS lazy:a: $(redis-cli -p $PORT EXISTS lazy:a)"
echo "expired_keys: $(redis-cli -p $PORT INFO stats | grep -E '^expired_keys:')"
echo "expired_stale_perc: $(redis-cli -p $PORT INFO stats | grep -E '^expired_stale_perc:')"
echo "===== 主动 GET lazy:a（触发惰性删除）====="
echo "GET lazy:a 返回: [$(redis-cli -p $PORT GET lazy:a)]"
echo "DBSIZE after GET: $(redis-cli -p $PORT DBSIZE)"
echo "expired_keys after GET: $(redis-cli -p $PORT INFO stats | grep -E '^expired_keys:')"
echo "===== 再 GET lazy:b ====="
redis-cli -p $PORT GET lazy:b >/dev/null
echo "DBSIZE after GET lazy:b: $(redis-cli -p $PORT DBSIZE)"
echo "expired_keys: $(redis-cli -p $PORT INFO stats | grep -E '^expired_keys:')"
echo "===== 未被访问的 lazy:c 仍在？====="
echo "DBSIZE: $(redis-cli -p $PORT DBSIZE)"
echo "KEYS *: $(redis-cli -p $PORT KEYS '*')"
echo "===== 重新开启定期删除，看 lazy:c 被回收 ====="
redis-cli -p $PORT DEBUG SET-ACTIVE-EXPIRE 1 2>&1 | head -2
sleep 2
echo "DBSIZE after active expire: $(redis-cli -p $PORT DBSIZE)"
echo "expired_keys: $(redis-cli -p $PORT INFO stats | grep -E '^expired_keys:')"
echo "===== SCAN/KEYS 是否会跳过已过期但未回收的 key ====="
redis-cli -p $PORT DEBUG SET-ACTIVE-EXPIRE 0 >/dev/null 2>&1
redis-cli -p $PORT SET scan:1 v EX 2 >/dev/null
sleep 2.5
echo "过期后 DBSIZE: $(redis-cli -p $PORT DBSIZE)"
echo "KEYS '*': $(redis-cli -p $PORT KEYS '*')  ← KEYS 会跳过过期 key"
echo "GET 后 DBSIZE: $(redis-cli -p $PORT DBSIZE)"
redis-cli -p $PORT DEBUG SET-ACTIVE-EXPIRE 1 >/dev/null 2>&1
echo "===== 清理 ====="
redis-cli -p $PORT flushall
redis-cli -p $PORT shutdown nosave 2>/dev/null
echo "done"
