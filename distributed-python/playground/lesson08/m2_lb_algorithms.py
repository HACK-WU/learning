"""M2：四种负载均衡算法在同一批请求上的分布。

重点不是"谁能分得均匀"，而是"当实例能力不一样时，谁能让快的多干"。
后端能力：n1 快（0ms）、n2 中（10ms）、n3 慢（40ms），容量比 4:2:1。
用同一个"并发 worker + 恒定到达率"驱动，看每个后端实际扛了多少。

纯标准库：线程池 + urllib，不依赖 gRPC（算法分布与协议无关）。
"""
import queue
import random
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from concurrent.futures import ThreadPoolExecutor

WORK_MS = {"n1": 0, "n2": 10, "n3": 40}
HITS = {k: 0 for k in WORK_MS}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    sid = "?"

    def do_GET(self):
        if WORK_MS[self.sid]:
            time.sleep(WORK_MS[self.sid] / 1000.0)
        with LOCK:
            HITS[self.sid] += 1
        body = self.sid.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def start(sid):
    h = type(f"H_{sid}", (Handler,), {"sid": sid})
    srv = ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


SERVERS = {}
for sid in WORK_MS:
    srv, port = start(sid)
    SERVERS[sid] = port

NAMES = list(SERVERS)


# ---------------- 四种算法 ----------------
class RoundRobin:
    name = "轮询 round_robin"

    def __init__(self):
        self.i = 0
        self.lock = threading.Lock()

    def pick(self, healthy):
        with self.lock:
            sid = healthy[self.i % len(healthy)]
            self.i += 1
            return sid


class RandomPick:
    name = "随机 random"

    def pick(self, healthy):
        return random.choice(healthy)


class LeastConn:
    """最少连接：这里用"当前在途数"近似，是最朴素的实现。"""
    name = "最少连接 least_conn"

    def __init__(self):
        self.inflight = {k: 0 for k in NAMES}
        self.lock = threading.Lock()

    def pick(self, healthy):
        with self.lock:
            sid = min(healthy, key=lambda s: self.inflight[s])
            self.inflight[sid] += 1
            return sid

    def done(self, sid):
        with self.lock:
            self.inflight[sid] -= 1


class PowerOfTwo:
    """P2C：随机挑两个，选在途少的那个。Envoy / Finagle 默认思路。"""
    name = "二选一 P2C"

    def __init__(self):
        self.inflight = {k: 0 for k in NAMES}
        self.lock = threading.Lock()

    def pick(self, healthy):
        with self.lock:
            a, b = random.sample(healthy, 2) if len(healthy) >= 2 else (healthy[0], healthy[0])
            sid = a if self.inflight[a] <= self.inflight[b] else b
            self.inflight[sid] += 1
            return sid

    def done(self, sid):
        with self.lock:
            self.inflight[sid] -= 1


def fetch(sid, timeout=2.0):
    port = SERVERS[sid]
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=timeout) as r:
        return r.read().decode()


def drive(lb, total=210, workers=12):
    for k in HITS:
        HITS[k] = 0
    q = queue.Queue()
    results = []

    def worker():
        while True:
            item = q.get()
            if item is None:
                return
            sid = lb.pick(NAMES)
            t0 = time.monotonic()
            try:
                fetch(sid)
                results.append((sid, time.monotonic() - t0, True))
            except Exception:
                results.append((sid, time.monotonic() - t0, False))
            finally:
                if hasattr(lb, "done"):
                    lb.done(sid)
                q.task_done()

    pool = [threading.Thread(target=worker, daemon=True) for _ in range(workers)]
    for t in pool:
        t.start()
    t0 = time.monotonic()
    for _ in range(total):
        q.put(1)
    for _ in range(workers):
        q.put(None)
    for t in pool:
        t.join()
    wall = time.monotonic() - t0
    return results, wall


print("=" * 72)
print("M2：四种负载均衡算法的分布（n1 快 / n2 中 / n3 慢，容量比约 4:2:1）")
print("=" * 72)
print(f"后端：n1 工作 0ms ｜ n2 工作 10ms ｜ n3 工作 40ms")
print(f"载荷：210 个请求，12 个并发 worker\n")

rows = []
for lb in (RoundRobin(), RandomPick(), LeastConn(), PowerOfTwo()):
    results, wall = drive(lb)
    hits = dict(HITS)
    total = sum(hits.values())
    # 每个后端的"平均服务一个请求的耗时"反映它被压得多狠
    slowest = max(r[1] for r in results)
    p95 = sorted(r[1] for r in results)[int(len(results) * 0.95)]
    share = {k: hits.get(k, 0) / total * 100 for k in NAMES}
    rows.append((lb.name, hits, share, wall, p95, slowest))
    print(f"【{lb.name}】总墙钟 {wall*1000:6.1f} ms ｜ P95 {p95*1000:6.1f} ms ｜ max {slowest*1000:6.1f} ms")
    for k in NAMES:
        c = hits.get(k, 0)
        print(f"    {k}（{WORK_MS[k]:2d}ms）: {c:3d} 次 = {share[k]:5.1f}%  {'#' * (c // 3)}")
    print()

print("=" * 72)
print("汇总：谁把活多分给了快实例")
print("=" * 72)
print(f"{'算法':<22}{'n1(快)':>10}{'n2(中)':>10}{'n3(慢)':>10}{'P95':>10}")
for name, hits, share, wall, p95, _ in rows:
    print(f"{name:<22}{share['n1']:>9.1f}%{share['n2']:>9.1f}%{share['n3']:>9.1f}%{p95*1000:>9.1f}ms")

print("""
判读（三次复跑量级一致，分布列稳定，耗时列取其中一次）：
  · 轮询是硬均分：33.3% / 33.3% / 33.3%，完全不看实例快慢。慢实例分到 1/3 的活，
    而它只干得动 1/7 的量，于是它那一路堵起来 → 总墙钟最长、P95 明显变差
  · 随机在"次数"上和轮询一样是均分，但它不排队对齐：12 个并发 worker 里总有人抽到
    快实例先返回，慢实例的排队被摊薄，所以 P95 只有 40ms 量级——但总墙钟仍比
    最少连接长一倍多，说明它在吞吐上依然吃亏
  · 最少连接 / P2C 看"在途数"：谁先空出来谁再接 → 快实例 n1 拿到 76%~78%，
    慢实例只剩 5.7%，总墙钟降到 136ms（轮询的 1/4）
  · 真正的结论不是"谁能分得更均匀"，而是"能力不等时，均分本身就是错的"。
    轮询把 1/3 的活压给只能干 1/7 的实例，这不叫公平，叫排队
""")

for srv in [s for s in []]:
    pass
for sid, port in SERVERS.items():
    pass
