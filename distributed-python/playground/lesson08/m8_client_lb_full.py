"""M8：一个能用的客户端负载均衡器，要处理哪几件事？

不是"写个轮询"就完事。真实实现要回答四个问题：
  ① 地址从哪来（这里用假注册中心，模拟"定期拉取"）
  ② 选哪个（round_robin / P2C）
  ③ 选中的那个刚挂掉怎么办（失败重试到别的实例，但不能重试非幂等接口）
  ④ 挂掉的实例什么时候回来（半开探测，不能永久拉黑）

纯标准库，用真实 HTTP 后端验证。
"""
import random
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HEALTH = {}
HITS = {}
LOCK = threading.Lock()


class Backend(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    sid = "?"

    def do_GET(self):
        with LOCK:
            HITS[self.sid] = HITS.get(self.sid, 0) + 1
        # /fail 路由用来模拟"业务失败"，/ 是正常
        if not HEALTH.get(self.sid, True):
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


def start(sid):
    h = type(f"B_{sid}", (Handler := Backend,), {"sid": sid})
    srv = ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


class Endpoint:
    __slots__ = ("addr", "inflight", "strikes", "ejected_until", "probing")

    def __init__(self, addr):
        self.addr = addr
        self.inflight = 0
        self.strikes = 0
        self.ejected_until = 0.0     # 0 表示健康
        self.probing = False         # 是否正在半开探测


class ClientLB:
    """一个最小但完整的客户端负载均衡器。"""

    def __init__(self, endpoints, eject_seconds=0.5, strike_limit=2, policy="p2c"):
        self.eps = [Endpoint(a) for a in endpoints]
        self.eject_seconds = eject_seconds
        self.strike_limit = strike_limit
        self.policy = policy
        self.lock = threading.Lock()

    # ---- ① 地址刷新（假注册中心）----
    def sync(self, addrs):
        with self.lock:
            known = {e.addr for e in self.eps}
            for a in addrs:
                if a not in known:
                    self.eps.append(Endpoint(a))
            self.eps = [e for e in self.eps if e.addr in addrs]

    # ---- ② 选一个 ----
    def _candidates(self, now):
        healthy = [e for e in self.eps if e.ejected_until <= now]
        if healthy:
            return healthy
        # 全都被摘了：放一个进去做半开探测，否则永远无法恢复
        probe = min(self.eps, key=lambda e: e.ejected_until)
        probe.probing = True
        return [probe]

    def pick(self):
        now = time.monotonic()
        with self.lock:
            cands = self._candidates(now)
            if self.policy == "rr":
                e = min(cands, key=lambda x: (x.inflight, x.addr))
            else:                                  # p2c
                if len(cands) == 1:
                    e = cands[0]
                else:
                    a, b = random.sample(cands, 2)
                    e = a if a.inflight <= b.inflight else b
            e.inflight += 1
            return e

    # ---- ③④ 记录结果 ----
    def report(self, ep, ok):
        now = time.monotonic()
        with self.lock:
            ep.inflight -= 1
            if ok:
                ep.strikes = 0
                ep.ejected_until = 0.0
                ep.probing = False
            else:
                ep.strikes += 1
                # 探测失败：立刻重新摘掉（不要等到下一次自然到期）
                if ep.probing or ep.strikes >= self.strike_limit:
                    ep.ejected_until = now + self.eject_seconds
                    ep.probing = False

    def healthy_count(self):
        now = time.monotonic()
        return sum(1 for e in self.eps if e.ejected_until <= now)


def fetch(addr, timeout=0.5):
    with urllib.request.urlopen(f"http://127.0.0.1:{addr}/", timeout=timeout) as r:
        return r.read().decode()


def call(lb, idempotent=True, timeout=0.5):
    """一次调用：选中 → 失败按幂等性决定是否换一个再试。"""
    ep = lb.pick()
    try:
        v = fetch(ep.addr, timeout)
        lb.report(ep, True)
        return v
    except Exception:
        lb.report(ep, False)
        if not idempotent:
            raise
        # 幂等才可以换一个实例重试
        others = [e for e in lb.eps if e is not ep and e.ejected_until <= time.monotonic()]
        if not others:
            raise
        ep2 = lb.pick()
        try:
            v = fetch(ep2.addr, timeout)
            lb.report(ep2, True)
            return v
        except Exception:
            lb.report(ep2, False)
            raise


print("=" * 78)
print("M8：客户端负载均衡的四个必答问题")
print("=" * 78)

srvs, addrs = [], []
for i in range(3):
    srv, p = start(f"n{i+1}")
    srvs.append(srv)
    addrs.append(str(p))
    HEALTH[f"n{i+1}"] = True

lb = ClientLB(addrs, eject_seconds=0.5, strike_limit=2, policy="p2c")

print("\n① 地址从哪来：定期 sync（这里手动调一次）")
lb.sync(addrs)
print(f"  已知端点: {[e.addr for e in lb.eps]}")

print("\n② 选哪个：P2C（随机两个选在途少的）")
for _ in range(12):
    call(lb)
    time.sleep(0.005)
print(f"  命中分布: {dict(HITS)}")

print("\n③ 选中的刚挂掉：n1 打挂，看客户端多久不再打它")
HITS.clear()
HEALTH["n1"] = False
ok = fail = 0
for _ in range(60):
    try:
        call(lb, idempotent=True)
        ok += 1
    except Exception:
        fail += 1
    time.sleep(0.005)
print(f"  60 次调用：成功 {ok} ｜ 失败 {fail}")
print(f"  被摘掉的端点: {[e.addr for e in lb.eps if e.ejected_until > time.monotonic()]}")
print(f"  当前健康数: {lb.healthy_count()} / 3")

print("\n④ 挂掉的什么时候回来：n1 恢复，等摘除期过 + 半开探测")
HEALTH["n1"] = True
time.sleep(0.6)                      # 超过 eject_seconds
ok2 = fail2 = 0
for _ in range(40):
    try:
        call(lb, idempotent=True)
        ok2 += 1
    except Exception:
        fail2 += 1
    time.sleep(0.005)
print(f"  40 次调用：成功 {ok2} ｜ 失败 {fail2}")
print(f"  当前健康数: {lb.healthy_count()} / 3  ← 探针成功后自动回归")
print(f"  最终命中分布: {dict(HITS)}")

for s in srvs:
    s.shutdown()
    s.server_close()

print("""
判读：
  · ① 地址必须来自外部（注册中心 / DNS / 配置中心），不能在代码里
  · ② 选择算法决定"能力不等时怎么分"——P2C 让快的多干，M2 已量化
  · ③ 单次失败不能直接判死：要有 strike_limit（连续失败阈值），
    否则一次网络抖动就把健康实例摘掉，反而制造故障
  · ④ 摘掉必须有期限（eject_seconds）并允许半开探测，
    否则实例修好了也永远回不来——这和课 7 熔断器的 Half-Open 是同一个道理
  · 还有一个没写进这四个问题的前提：重试只对幂等接口安全（课 6）。
    非幂等接口换实例重试，等于可能重复下单两次
""")
