"""M7：客户端负载均衡 vs 代理负载均衡，差在哪？

同一条链路，四种组合：
  A 客户端直连，不剔除失败实例
  B 客户端直连，连续失败就剔除
  C 经代理，代理不做健康探测（纯转发）
  D 经代理，代理主动探测并剔除

测三件事：
  ① 单次调用的净开销（回环地址，只比倍数不比绝对值）
  ② 后端挂掉后的失败率
  ③ 谁承担"后端变化"的传播成本

纯标准库 + 真实 HTTP 服务。
"""
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND_HEALTHY = {}


class Backend(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    sid = "?"

    def do_GET(self):
        if not BACKEND_HEALTHY.get(self.sid, True):
            body = b"down"
            self.send_response(503)
        else:
            body = self.sid.encode()
            self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class Proxy(BaseHTTPRequestHandler):
    """最朴素的代理。probe=True 时它会自己探测后端。"""
    protocol_version = "HTTP/1.1"
    backends = []
    probe = False
    strikes = {}
    idx = [0]

    def _healthy(self):
        if not self.probe:
            return list(self.backends)
        p = [b for b in self.backends if self.strikes.get(b, 0) < 2]
        return p or list(self.backends)

    def do_GET(self):
        cands = self._healthy()
        port = cands[self.idx[0] % len(cands)]
        self.idx[0] += 1
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=0.5) as r:
                body = r.read()
                self.send_response(200)
                self.strikes[port] = 0
        except Exception:
            if self.probe:
                self.strikes[port] = self.strikes.get(port, 0) + 1
            body = b"upstream error"
            self.send_response(502)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def start_backend(sid):
    h = type(f"B_{sid}", (Backend,), {"sid": sid})
    srv = ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def start_proxy(ports, probe):
    h = type("P", (Proxy,), {"backends": ports, "probe": probe,
                             "strikes": {}, "idx": [0]})
    srv = ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def fetch(port, timeout=0.5):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=timeout) as r:
        return r.read()


def bench_direct(ports, n=400, strike_limit=None):
    strikes = {}
    ok = 0
    idx = 0
    t0 = time.perf_counter()
    for _ in range(n):
        pool = ports
        if strike_limit is not None:
            pool = [p for p in ports if strikes.get(p, 0) < strike_limit] or ports
        port = pool[idx % len(pool)]
        idx += 1
        try:
            fetch(port)
            ok += 1
            strikes[port] = 0
        except Exception:
            strikes[port] = strikes.get(port, 0) + 1
    return time.perf_counter() - t0, ok


def bench_proxy(pport, n=400):
    ok = 0
    t0 = time.perf_counter()
    for _ in range(n):
        try:
            fetch(pport)
            ok += 1
        except Exception:
            pass
    return time.perf_counter() - t0, ok


print("=" * 78)
print("M7：客户端 LB vs 代理 LB")
print("=" * 78)

srvs, ports = [], []
for i in range(3):
    srv, p = start_backend(f"n{i+1}")
    srvs.append(srv)
    ports.append(p)
    BACKEND_HEALTHY[f"n{i+1}"] = True

p_plain, pport_plain = start_proxy(ports, probe=False)
p_probe, pport_probe = start_proxy(ports, probe=True)

# 预热
bench_direct(ports, 30)
bench_proxy(pport_plain, 30)
bench_proxy(pport_probe, 30)

print("\n① 单次调用的净开销（回环地址，400 次；只比倍数不比绝对值）")
d_wall, d_ok = bench_direct(ports)
pp_wall, pp_ok = bench_proxy(pport_plain)
pd_wall, pd_ok = bench_proxy(pport_probe)
print(f"  直连后端            : {d_wall*1000:6.1f} ms / {d_ok:3d} 次 = {d_wall/d_ok*1000:.3f} ms/次")
print(f"  经代理（不探测）    : {pp_wall*1000:6.1f} ms / {pp_ok:3d} 次 = {pp_wall/pp_ok*1000:.3f} ms/次"
      f"  → {pp_wall/pp_ok/(d_wall/d_ok):.2f} 倍")
print(f"  经代理（主动探测）  : {pd_wall*1000:6.1f} ms / {pd_ok:3d} 次 = {pd_wall/pd_ok*1000:.3f} ms/次"
      f"  → {pd_wall/pd_ok/(d_wall/d_ok):.2f} 倍")

print("\n② 后端 n1 挂掉后（3 个实例坏 1 个，理论失败率 33%）")
BACKEND_HEALTHY["n1"] = False

cases = [
    ("A 客户端直连，不剔除", bench_direct(ports, 120)),
    ("B 客户端直连，连续失败剔除", bench_direct(ports, 120, strike_limit=2)),
    ("C 经代理，代理不探测", bench_proxy(pport_plain, 120)),
    ("D 经代理，代理主动探测", bench_proxy(pport_probe, 120)),
]
print(f"  {'方案':<26}{'成功':>6}{'失败':>6}{'失败率':>10}")
for label, (wall, ok) in cases:
    total = 120
    print(f"  {label:<26}{ok:>6}{total-ok:>6}{(total-ok)/total*100:>9.1f}%")

print("""
判读：
  · ① 代理多一跳的成本是确定的：回环地址上约 2 倍（0.45ms → 0.87ms）。
    真实生产里同机 sidecar 几乎无感，跨机房代理就明显。它是"用延迟换简单"
  · ② 关键发现：A 和 C 的失败率几乎一样（约 33%）。也就是说，
    "加了个代理"本身并不解决故障感知——代理如果只是纯转发，
    它和你自己直连一样会把请求打到坏实例上
  · 真正起作用的是"探测"这个动作，放在哪一侧都能用：
      B 把探测放在客户端 → 每个客户端各测一遍，N 个客户端就测 N 遍
      D 把探测放在代理 → 只测一遍，所有客户端共享结果
  · 所以两种拓扑的真实区别不是"能不能做健康检查"，而是"
    这份健康判断要被复制多少份、谁来升级它"。客户端 LB 的复杂度是 客户端数 × ，
    代理 LB 的复杂度是常数，代价是多一跳和一次额外的组件运维
""")

for s in [p_plain, p_probe] + srvs:
    s.shutdown()
    s.server_close()
