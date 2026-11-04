"""M3b：gRPC 遇上 L4 负载均衡——一条连接把所有调用绑在一个实例上。

用真实 gRPC（grpcio）+ 一个手写的 TCP 转发器（模拟 NLB / K8s Service 的
L4 行为：按连接转发，不看里面有几个 RPC）。

测两轮：
  轮 1：1 个客户端，12 次 RPC → 看 3 个后端各收到多少
  轮 2：6 个客户端各 12 次 → 看"客户端被摊到后端"之后是否均匀

对照：把同一个客户端改成 round_robin + 多地址直连（L7 式逐次选择）。
"""
import socket
import threading
import time

import grpc

from _grpc_backend import (
    ROUND_ROBIN_OPTS,
    Registry,
    make_server,
    make_stub,
    target_of,
)


class TcpForwarder:
    """最朴素的 L4 负载均衡：accept 后按轮询挑一个后端，然后双向搬字节。"""

    def __init__(self, backends):
        self.backends = backends
        self.i = 0
        self.lock = threading.Lock()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(64)
        self.port = self.sock.getsockname()[1]
        self.picked = []
        threading.Thread(target=self._serve, daemon=True).start()

    def _pick(self):
        with self.lock:
            p = self.backends[self.i % len(self.backends)]
            self.i += 1
            self.picked.append(p)
            return p

    def _pipe(self, src, dst):
        try:
            while True:
                data = src.recv(65536)
                if not data:
                    break
                dst.sendall(data)
        except Exception:
            pass
        finally:
            for s in (src, dst):
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except Exception:
                    pass
                try:
                    s.close()
                except Exception:
                    pass

    def _serve(self):
        while True:
            try:
                c, _ = self.sock.accept()
            except OSError:
                return
            upstream_port = self._pick()
            try:
                u = socket.create_connection(("127.0.0.1", upstream_port), timeout=5)
            except Exception:
                c.close()
                continue
            threading.Thread(target=self._pipe, args=(c, u), daemon=True).start()
            threading.Thread(target=self._pipe, args=(u, c), daemon=True).start()

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


print("=" * 78)
print("M3b：gRPC + L4 负载均衡（按连接转发）")
print("=" * 78)

# ---------- 轮 1：单客户端经 L4 代理 ----------
reg = Registry()
servers, real_ports = [], []
for i in range(3):
    s, bound = make_server(f"n{i+1}", 0, reg)
    servers.append(s)
    real_ports.append(bound)

fwd = TcpForwarder(real_ports)

ch = grpc.insecure_channel(f"127.0.0.1:{fwd.port}")
stub = make_stub(ch)
grpc.channel_ready_future(ch).result(timeout=10)
for _ in range(12):
    stub(b"", timeout=5)

hits = reg.snapshot()
print("\n轮 1：1 个客户端 × 12 次 RPC，经 L4 代理（3 个后端）")
print(f"  代理建立的连接数: {len(fwd.picked)}  ← 1 个客户端通常只开 1 条 HTTP/2 连接")
for sid in ["n1", "n2", "n3"]:
    c = hits.get(sid, 0)
    print(f"  {sid}: {c:2d} 次  {'#' * c}")
print(f"  → 实际用到的后端: {sum(1 for v in hits.values() if v)} / 3")
ch.close()

# ---------- 轮 2：6 个客户端经同一个 L4 代理 ----------
reg.reset()
fwd2 = TcpForwarder(real_ports)
chans = []
for _ in range(6):
    # 关掉进程内 subchannel 池复用：不关的话 6 个 channel 会共用同一条 TCP 连接，
    # 那样测出来的是"gRPC 自己做了连接复用"，不是"L4 按连接分发"的行为
    c = grpc.insecure_channel(
        f"127.0.0.1:{fwd2.port}",
        options=[("grpc.use_local_subchannel_pool", 1)],
    )
    s = make_stub(c)
    grpc.channel_ready_future(c).result(timeout=10)
    chans.append((c, s))
    for _ in range(12):
        s(b"", timeout=5)

hits2 = reg.snapshot()
print("\n轮 2：6 个客户端 × 12 次 RPC，经同一个 L4 代理")
print(f"  代理建立的连接数: {len(fwd2.picked)}")
for sid in ["n1", "n2", "n3"]:
    c = hits2.get(sid, 0)
    print(f"  {sid}: {c:2d} 次  {'#' * c}")
tot = sum(hits2.values())
shares = {sid: hits2.get(sid, 0) / tot * 100 for sid in ["n1", "n2", "n3"]}
print(f"  分布: " + " ｜ ".join(f"{k} {v:4.1f}%" for k, v in shares.items()))
worst = max(shares.values())
print(f"  → 最忙的实例拿到 {worst:.1f}%（理想均分 33.3%）")
for c, _ in chans:
    c.close()

# ---------- 轮 3：客户端流量不均（一个重客户端 + 五个轻客户端）----------
reg.reset()
fwd3 = TcpForwarder(real_ports)
heavy = grpc.insecure_channel(
    f"127.0.0.1:{fwd3.port}", options=[("grpc.use_local_subchannel_pool", 1)]
)
hstub = make_stub(heavy)
grpc.channel_ready_future(heavy).result(timeout=10)
for _ in range(90):                       # 重客户端：90 次
    hstub(b"", timeout=5)

lights = []
for _ in range(5):
    c = grpc.insecure_channel(
        f"127.0.0.1:{fwd3.port}", options=[("grpc.use_local_subchannel_pool", 1)]
    )
    s = make_stub(c)
    grpc.channel_ready_future(c).result(timeout=10)
    lights.append((c, s))
    for _ in range(2):                    # 轻客户端：各 2 次
        s(b"", timeout=5)

hits4 = reg.snapshot()
tot4 = sum(hits4.values())
print("\n轮 3：1 个重客户端（90 次）+ 5 个轻客户端（各 2 次），共 100 次")
print(f"  代理建立的连接数: {len(fwd3.picked)}")
for sid in ["n1", "n2", "n3"]:
    c = hits4.get(sid, 0)
    print(f"  {sid}: {c:3d} 次 ({c/tot4*100:5.1f}%)  {'#' * (c // 2)}")
worst4 = max(hits4.get(s, 0) for s in ["n1", "n2", "n3"]) / tot4
print(f"  → 最忙实例 {worst4*100:.1f}%（理想 33.3%），倾斜 {worst4*3:.2f} 倍")
heavy.close()
for c, _ in lights:
    c.close()
fwd3.close()

# ---------- 对照：客户端自己 round_robin 多地址 ----------
reg.reset()
ch3 = grpc.insecure_channel(target_of(real_ports), options=ROUND_ROBIN_OPTS)
stub3 = make_stub(ch3)
grpc.channel_ready_future(ch3).result(timeout=10)
for _ in range(12):
    stub3(b"", timeout=5)
hits3 = reg.snapshot()
print("\n对照：同一批后端，客户端用 round_robin 直连多地址（L7 式逐次选择）")
for sid in ["n1", "n2", "n3"]:
    c = hits3.get(sid, 0)
    print(f"  {sid}: {c:2d} 次  {'#' * c}")
print(f"  → 实际用到的后端: {sum(1 for v in hits3.values() if v)} / 3，"
      f"每后端 {hits3.get('n1',0)}/{hits3.get('n2',0)}/{hits3.get('n3',0)}")
ch3.close()

fwd.close()
fwd2.close()
for s in servers:
    s.stop(0)

print("""
判读：
  · gRPC 跑在 HTTP/2 上，一条连接里能复用几百个并发 RPC。
    所以"按连接转发"的 L4 负载均衡，对 gRPC 等于"按客户端分配实例"：
    一个客户端 = 一条连接 = 一个后端
  · 轮 1 就是这么塌的：12 个 RPC 全落在同一个实例上，另外两个完全空闲
  · 轮 2 靠"客户端数量多"侥幸摊开，但粒度仍是"整个客户端"，
    客户端数量少、或客户端流量差异大时，分布会非常偏
  · 两条正路（官方文档的两种方案）：
      ① 客户端负载均衡：客户端拿全量地址，每次调用自己选（round_robin / P2C）
      ② L7 代理：代理理解 HTTP/2，把连接里的每个 RPC 分开转发
    唯一不能指望的是"L4 负载均衡能自动摊平 gRPC"——它看不到 RPC 边界
""")
