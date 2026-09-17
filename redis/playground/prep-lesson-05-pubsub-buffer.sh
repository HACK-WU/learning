#!/usr/bin/env bash
# 课 5 补充实验：Pub/Sub 输出缓冲区堆积（用 Python 订阅者，精确抓 omem 与断开）
set -u

python3 - <<'PY'
import socket, subprocess, time, os, sys, signal

PORT = 7206
DIR = "/tmp/redis-l05b2"
os.makedirs(DIR, exist_ok=True)

srv = subprocess.Popen(
    ["redis-server", "--port", str(PORT), "--bind", "127.0.0.1", "--dir", DIR,
     "--save", "", "--appendonly", "no",
     "--client-output-buffer-limit", "pubsub 1048576 262144 5"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1.2)

def conn():
    s = socket.create_connection(("127.0.0.1", PORT))
    return s, s.makefile('rwb')

def cmd(s, f, *args):
    out = b"*%d\r\n" % len(args)
    for a in args:
        a = str(a).encode()
        out += b"$%d\r\n%s\r\n" % (len(a), a)
    s.sendall(out); f.flush()
    return read_reply(f)

def read_reply(f):
    line = f.readline().strip()
    if not line: return None
    if line.startswith(b'$'):
        n = int(line[1:])
        if n == -1: return None
        return f.read(n+2)[:-2].decode()
    if line.startswith(b':'): return int(line[1:])
    if line.startswith(b'+'): return line[1:].decode()
    if line.startswith(b'-'): return Exception(line.decode())
    if line.startswith(b'*'):
        n = int(line[1:])
        if n == -1: return None
        return [read_reply(f) for _ in range(n)]
    return line.decode()

# ① 起一个只订阅、不读消息的订阅者
sub, subf = conn()
sub.sendall(b"*2\r\n$9\r\nSUBSCRIBE\r\n$9\r\nslow.chan\r\n")
subf.flush()
time.sleep(0.5)
print("① 订阅者已连接（只订阅，从不读取）")

# ② 用 admin 连接看 omem
adm, admf = conn()
def sub_clients():
    res = cmd(adm, admf, "CLIENT", "LIST")
    out = []
    for line in (res or "").split("\n"):
        if "cmd=subscribe" in line:
            d = dict(kv.split("=", 1) for kv in line.split() if "=" in kv)
            out.append(d)
    return out

c0 = sub_clients()
print("② 发布前，subscribe 客户端 omem =", [c.get("omem") for c in c0])

# ③ 持续发布大消息给 slow.chan
pub, pubf = conn()
msg = b"x" * 1000
sent = 0
samples = []
for i in range(4000):
    try:
        pub.sendall(b"*3\r\n$7\r\nPUBLISH\r\n$9\r\nslow.chan\r\n$%d\r\n%s\r\n" % (len(msg), msg))
        sent += len(msg)
    except Exception as e:
        print("   发布端异常：", e); break
    if i % 500 == 0:
        try:
            pub.recv(65536)
        except Exception:
            pass
        cs = sub_clients()
        if cs:
            samples.append((i, cs[0].get("omem")))
        else:
            samples.append((i, "已断开"))
            break
print("③ 已发布 %.2f MB" % (sent/1024/1024))
print("   omem 采样（发布条数 -> 输出缓冲区字节）：")
for i, om in samples:
    print("     第 %4d 条 -> omem = %s" % (i, om))

time.sleep(1)
cs = sub_clients()
print("④ 发布结束后 subscribe 客户端数 =", len(cs), "（0 = 已被服务端断开保护）")
if cs:
    print("   omem =", [c.get("omem") for c in cs])

# ⑤ 确认订阅者确实收不到 / 已被踢
try:
    sub.sendall(b"*1\r\n$4\r\nPING\r\n"); subf.flush()
    r = read_reply(subf)
    print("⑤ 订阅者连接 PING ->", r)
except Exception as e:
    print("⑤ 订阅者连接已不可用：", e)

srv.send_signal(signal.SIGTERM)
try:
    srv.wait(timeout=5)
except Exception:
    srv.kill()
subprocess.run(["rm", "-rf", DIR])
print("缓冲区实验结束。")
PY
