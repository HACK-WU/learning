#!/usr/bin/env bash
# 课 8 分布式锁：错误解锁（裸 DEL）导致误删他人锁 的复现脚本
# 环境：WSL Ubuntu 24.04 + Redis 8.10.1
set -u

DIR=/tmp/redis-l08lock
PORT=7202
mkdir -p $DIR

redis-server --port $PORT --bind 127.0.0.1 --dir $DIR \
  --save '' --appendonly no >/dev/null 2>&1 &
SRV_PID=$!
sleep 1.2
R() { redis-cli -p "$PORT" "$@"; }

echo "===== 场景：A 加锁 -> A 执行超时 -> 锁自动过期 -> B 加锁 -> A 完成 -> A 裸 DEL ====="
echo

echo "① A 加锁（value='1'，TTL 1 秒）"
R SET lock:order '1' EX 1 NX
echo "   当前锁值：$(R GET lock:order)   TTL：$(R TTL lock:order)"

echo "② 模拟 A 的业务执行超过了 TTL（sleep 1.5s）"
sleep 1.5
echo "   锁已过期？ TTL = $(R TTL lock:order)   值 = $(R GET lock:order)"

echo "③ B 抢到锁（value 同样是 '1'）"
R SET lock:order '1' EX 10 NX
echo "   当前锁值：$(R GET lock:order)   TTL：$(R TTL lock:order)"

echo "④ A 执行完毕，执行 finally 里的裸 DEL"
R DEL lock:order
echo "   DEL 返回：已删除 1 个 key"
echo "   现在锁还在吗？ GET lock:order = $(R GET lock:order)"
echo
echo ">>> 结论：B 持有的锁被 A 删掉了。此时 C 也能加锁，互斥完全失效。"
R SET lock:order '1' EX 10 NX
echo "   C 加锁结果：$(R GET lock:order)  ← 本应失败，却成功了"
R DEL lock:order > /dev/null

echo
echo "===== 正确做法：UUID value + Lua 比对再释放 ====="
R SET lock:order 'A-uuid-aaaa' EX 1 NX > /dev/null
sleep 1.5
R SET lock:order 'B-uuid-bbbb' EX 10 NX > /dev/null
echo "① 当前锁属于 B：$(R GET lock:order)"
echo "② A 用 Lua 释放（KEYS[1]=锁名, ARGV[1]=A 自己的 uuid）："
R --eval /dev/stdin lock:order , A-uuid-aaaa <<'EOF'
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
EOF
echo "   Lua 返回 0 = 没删（正确）"
echo "   锁还在吗？ $(R GET lock:order)  ← 仍是 B 的，未被误删"
echo
echo "③ B 自己释放："
R --eval /dev/stdin lock:order , B-uuid-bbbb <<'EOF'
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
EOF
echo "   Lua 返回 1 = 已删（正确），现在锁值 = $(R GET lock:order)"

R shutdown nosave 2>/dev/null
wait $SRV_PID 2>/dev/null
rm -rf $DIR
echo; echo "锁实验结束，实例已清理。"
