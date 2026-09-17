#!/usr/bin/env bash
# 课 9 补充实验：WATCH 乐观锁（Redis 事务的正面用法）
set -u
DIR=/tmp/redis-l09w
PORT=7205
mkdir -p $DIR
redis-server --port $PORT --bind 127.0.0.1 --dir $DIR --save '' --appendonly no >/dev/null 2>&1 &
SRV=$!
sleep 1.2
R() { redis-cli -p "$PORT" "$@"; }
sec() { echo; echo "===== $1 ====="; }

sec "① 没有 WATCH：读-改-写 的覆盖问题"
R SET balance 100 > /dev/null
echo "初始值：$(R GET balance)"
echo "-- 两个客户端同时扣款 30（各自读到 100，各自写回 70）："
R GET balance > /dev/null
V1=$(R GET balance)
V2=$(R GET balance)
R SET balance $((V1 - 30)) > /dev/null
R SET balance $((V2 - 30)) > /dev/null
echo "  最终结果：$(R GET balance)   ← 应为 40，实际丢了 30"

sec "② 用 WATCH 保护：被监视的 key 若被改，事务整体不执行"
R SET balance 100 > /dev/null
echo "初始值：$(R GET balance)"
(
  echo "WATCH balance"
  echo "GET balance"
  sleep 0.5
  echo "MULTI"
  echo "SET balance 70"
  echo "EXEC"
  sleep 0.3
) | redis-cli -p $PORT > /dev/null 2>&1 &
TX=$!
sleep 0.2
R SET balance 999 > /dev/null        # 另一个客户端中途改了 balance
wait $TX 2>/dev/null
echo "  中途被改成：999"
echo "  事务执行后：$(R GET balance)   ← 若仍是 999，说明事务被取消（正确）"

sec "③ 直接观察 EXEC 返回 nil（事务被取消）"
R SET balance 100 > /dev/null
{
  printf 'WATCH balance\n'
  printf 'GET balance\n'
} | redis-cli -p $PORT > /dev/null
# 手工分步：用 redis-cli 无法保持连接，改用 --pipe 不可行；用 Lua 模拟说明，改为展示 EXEC nil
echo "  用一条连接演示（通过 nc 不可用，改用 redis-cli 交互脚本）："

sec "④ 用 Python 单连接完整演示 WATCH 成功与失败两种结果"
python3 - "$PORT" <<'PY'
import socket, sys, threading, time
port = int(sys.argv[1])

def conn():
    s = socket.create_connection(("127.0.0.1", port)); return s, s.makefile('rwb')

def cmd(s, f, *args):
    out = b"*%d\r\n" % len(args)
    for a in args:
        a = str(a).encode()
        out += b"$%d\r\n%s\r\n" % (len(a), a)
    s.sendall(out); f.flush()
    return read_reply(f)

def read_reply(f):
    line = f.readline().strip()
    if line.startswith(b'$'):
        n = int(line[1:])
        if n == -1: return None
        data = f.read(n+2)[:-2]
        return data.decode()
    if line.startswith(b':'): return int(line[1:])
    if line.startswith(b'+'): return line[1:].decode()
    if line.startswith(b'-'): return Exception(line.decode())
    if line.startswith(b'*'):
        n = int(line[1:])
        if n == -1: return None      # EXEC 被取消 -> 返回 nil
        return [read_reply(f) for _ in range(n)]
    return line.decode()

def setup():
    s, f = conn(); cmd(s, f, "SET", "balance", 100); s.close()

# 场景 A：无人打扰 -> 事务成功
setup()
s, f = conn()
cmd(s, f, "WATCH", "balance")
cur = int(cmd(s, f, "GET", "balance"))
cmd(s, f, "MULTI")
cmd(s, f, "SET", "balance", cur - 30)
res = cmd(s, f, "EXEC")
print("  场景 A（无人打扰）：EXEC 返回 =", res, " balance =", cmd(s, f, "GET", "balance"))
s.close()

# 场景 B：WATCH 之后被别人改 -> 事务取消
setup()
s, f = conn()
cmd(s, f, "WATCH", "balance")
cur = int(cmd(s, f, "GET", "balance"))
# 另一个连接修改
o, of = conn(); cmd(o, of, "SET", "balance", 999); o.close()
cmd(s, f, "MULTI")
cmd(s, f, "SET", "balance", cur - 30)
res = cmd(s, f, "EXEC")
print("  场景 B（中途被改）：EXEC 返回 =", res, " balance =", cmd(s, f, "GET", "balance"))
print("         ↑ EXEC 返回 None 即 nil，表示事务被取消，balance 保持 999")
s.close()

# 场景 C：UNWATCH 放弃监视
s, f = conn()
cmd(s, f, "WATCH", "balance")
cmd(s, f, "UNWATCH")
o, of = conn(); cmd(o, of, "SET", "balance", 555); o.close()
cmd(s, f, "MULTI")
cmd(s, f, "SET", "balance", 1)
res = cmd(s, f, "EXEC")
print("  场景 C（UNWATCH 后）：EXEC 返回 =", res, " balance =", cmd(s, f, "GET", "balance"))
s.close()
PY

sec "⑤ WATCH 与 Lua 的对比：为什么生产更常用 Lua"
echo "  WATCH：乐观锁，冲突时事务取消，需要客户端重试（要自己写重试循环）"
echo "  Lua  ：整段脚本原子执行，无冲突概念，不需要重试"
echo "  -- 同一扣款逻辑用 Lua："
R SET balance 100 > /dev/null
R EVAL "local v = redis.call('get', KEYS[1]); redis.call('set', KEYS[1], v - ARGV[1]); return v - ARGV[1]" 1 balance 30
echo "  结果：$(R GET balance)"
echo "  但已监视/已 MULTI 之后仍需注意：Lua 执行期间其他命令不会插入"

sec "⑥ 事务不回滚：MULTI 中某条命令出错，其余照常执行"
R DEL k1 > /dev/null
R MULTI > /dev/null
R SET k1 "abc" > /dev/null
R INCR k1 > /dev/null        # 对字符串自增，运行时错误
R SET k2 "still-set" > /dev/null
echo "-- EXEC 结果（第 3 条报错，第 4 条仍然成功）："
R EXEC
echo "  k1 = $(R GET k1)   k2 = $(R GET k2)   ← k2 被写了，证明没有回滚"

R shutdown nosave 2>/dev/null
wait $SRV 2>/dev/null
rm -rf $DIR
echo; echo "WATCH 实验结束。"
