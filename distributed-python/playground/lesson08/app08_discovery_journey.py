"""应用实战 08：实例扩缩容，三段演进（四幕同场景对照）

同一套后端，只改客户端：
  V1 硬编码地址
  V2 注册中心 + 轮询（心跳 TTL + 客户端缓存）
  V3 客户端 LB + 健康检查（strike 摘流 + 半开探测 + P2C）

四幕对 V2/V3 完全同口径，方便逐个数字对比：
  幕 1 常态：5 个实例，30 次调用
  幕 2 n1 半死：能连上但返回 503，进程还在、心跳照发
  幕 3 n1 全死：连不上、也不发心跳
  幕 4 n1 以新端口回来

纯标准库，python3 直接跑。约 30 秒。
"""
import itertools
import random
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()
HITS = {}            # 成功响应计数（按实例名）
ATTEMPTS = {}        # 被打次数（不管成败）
READY = {}           # 实例是否还能接活（False → 503）
HB_ALIVE = set()     # 正在发心跳的实例名

HOST = "127.0.0.1"


# ------------------------------------------------------------------ 后端
class Backend(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    sid = "?"

    def do_GET(self):
        with LOCK:
            ATTEMPTS[self.sid] = ATTEMPTS.get(self.sid, 0) + 1
            alive = READY.get(self.sid, True)
            if alive:
                HITS[self.sid] = HITS.get(self.sid, 0) + 1
        if not alive:
            # 进程还活着但接不了活：预热没完成 / 依赖挂了 / 正在摘流
            self.send_response(503)
            body = b"not-ready"
        else:
            self.send_response(200)
            body = self.sid.encode()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class Node:
    """一个实例：端口固定，可以反复"重启"（换新端口）。"""

    def __init__(self, name, port):
        self.name = name
        self.port = port
        self.srv = None

    def boot(self):
        h = type(f"B_{self.name}", (Backend,), {"sid": self.name})
        self.srv = ThreadingHTTPServer((HOST, 0), h)
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        READY[self.name] = True
        HB_ALIVE.add(self.name)
        return self.port

    def kill(self):
        """进程真死：停止监听 + 退出心跳集合。"""
        HB_ALIVE.discard(self.name)
        if self.srv:
            self.srv.shutdown()
            self.srv.server_close()
            self.srv = None


def fetch(port, timeout=0.4):
    with urllib.request.urlopen(f"http://{HOST}:{port}/", timeout=timeout) as r:
        return r.read().decode()


def reset():
    with LOCK:
        HITS.clear()
        ATTEMPTS.clear()


def snap(counter):
    with LOCK:
        return dict(counter)


def banner(tag):
    print(f"\n{'-' * 76}\n{tag}\n{'-' * 76}")


def flat(d):
    return {k: v for k, v in sorted(d.items()) if v}


# ------------------------------------------------------------------ 注册中心
class Registry:
    """心跳 + TTL。超过 hb_ttl 没心跳的实例从名单里消失。"""

    def __init__(self, hb_ttl=2.0):
        self.hb_ttl = hb_ttl
        self.ports = {}
        self.last_seen = {}
        self.lock = threading.Lock()

    def register(self, name, port):
        with self.lock:
            self.ports[name] = port
            self.last_seen[name] = time.monotonic()

    def heartbeat(self, name):
        with self.lock:
            if name in self.ports:
                self.last_seen[name] = time.monotonic()

    def snapshot(self):
        now = time.monotonic()
        with self.lock:
            return [(n, p) for n, p in sorted(self.ports.items())
                    if now - self.last_seen[n] <= self.hb_ttl]

    def run_heartbeats(self, period=0.25):
        def loop():
            while True:
                for n in list(HB_ALIVE):
                    self.heartbeat(n)
                time.sleep(period)

        threading.Thread(target=loop, daemon=True).start()


# ------------------------------------------------------------------ V1
def v1_hardcoded(nodes, scale_out):
    banner("V1 硬编码地址：SERVER_PORT = 常量")
    SERVER_PORT = nodes["n1"].port
    print(f"客户端代码：SERVER_PORT = {SERVER_PORT}   ← 写死，n1 的端口")

    def burst(n=30):
        reset()
        ok = fail = 0
        for _ in range(n):
            try:
                fetch(SERVER_PORT)
                ok += 1
            except Exception:
                fail += 1
        return ok, fail, snap(ATTEMPTS)

    ok, fail, h = burst()
    print(f"\n幕 1 初始 3 个实例：成功 {ok}/{ok + fail}  被打分布 {flat(h)}")
    print("       → 3 个实例只用到 1 个，利用率 33.3%")

    new = scale_out("n4", "n5")
    ok, fail, h = burst()
    print(f"幕 2 扩容到 5 个：成功 {ok}/{ok + fail}  被打分布 {flat(h)}")
    print("       → 有效容量仍是 1/5 = 20.0%，扩了等于没扩")

    READY["n1"] = False
    ok, fail, h = burst()
    print(f"幕 3 n1 不可用：成功 {ok}/{ok + fail}  被打分布 {flat(h) or '{}'}")
    print(f"       → 0% 成功。另 4 个实例活着，客户端只认识端口 {SERVER_PORT}")

    READY["n1"] = True
    ok, fail, h = burst()
    print(f"幕 4 n1 恢复：成功 {ok}/{ok + fail}  被打分布 {flat(h)}")
    print("       → 恢复靠的是「还是原来那个端口」；换了端口就永远回不来")


# ------------------------------------------------------------------ V2
class PollingClient:
    """V2：定期从注册中心拉名单，本地缓存 pull 秒，轮询选择。"""

    def __init__(self, registry, pull_seconds=0.2):
        self.reg = registry
        self.pull = pull_seconds
        self.cache = []
        self.fetched_at = -1e9
        self.turn = itertools.count()

    def refresh(self, force=False):
        now = time.monotonic()
        if force or now - self.fetched_at >= self.pull:
            self.cache = self.reg.snapshot()
            self.fetched_at = now
        return self.cache

    def call(self):
        eps = self.refresh()
        if not eps:
            raise RuntimeError("registry returned no endpoints")
        name, port = eps[next(self.turn) % len(eps)]
        return fetch(port), name


def run_stream(call, seconds, sleep=0.02):
    """打 seconds 秒，返回 (总次数, 失败次数, 失败秒数, 每实例被打次数)。"""
    reset()
    t0 = time.monotonic()
    total = fail = 0
    fail_times = []
    while time.monotonic() - t0 < seconds:
        try:
            call()
        except Exception:
            fail += 1
            fail_times.append(time.monotonic() - t0)
        total += 1
        time.sleep(sleep)
    return total, fail, fail_times, snap(ATTEMPTS)


def report_stream(label, total, fail, fail_times):
    pct = fail / total * 100 if total else 0.0
    if fail:
        last = max(fail_times)
        print(f"       {label}：共 {total} 次｜失败 {fail}（{pct:.1f}%）"
              f"｜最后一次失败在 {last:.2f}s")
    else:
        print(f"       {label}：共 {total} 次｜失败 0（0.0%）｜全程无失败")


def v2_registry(reg, nodes):
    banner("V2 注册中心 + 轮询：名单来自心跳，客户端缓存 200ms")
    client = PollingClient(reg, pull_seconds=0.2)
    client.refresh(force=True)

    def burst(n=30):
        reset()
        ok = fail = 0
        for _ in range(n):
            try:
                client.call()
                ok += 1
            except Exception:
                fail += 1
        return ok, fail, snap(ATTEMPTS)

    ok, fail, h = burst()
    print(f"\n幕 1 常态 5 个实例：成功 {ok}/{ok + fail}  被打分布 {flat(h)}")
    print("       → 5 个全用上，每个 6 次（V1 只会用 1 个）")

    print("\n幕 2 n1 半死：能连上、返回 503，进程还在、心跳照发")
    READY["n1"] = False
    total, fail, ft, att = run_stream(client.call, 3.0)
    report_stream("3 秒内", total, fail, ft)
    print(f"       n1 被白打 {att.get('n1', 0)} 次")
    print("       → 注册中心只看心跳，永远发现不了「活着但接不了活」")

    print("\n幕 3 n1 全死：连不上、也不再发心跳")
    nodes["n1"].kill()
    total, fail, ft, att = run_stream(client.call, 3.2)
    report_stream("3.2 秒内", total, fail, ft)
    print(f"       → 自动止血，止血点在 {max(ft):.2f}s"
          f"（= 心跳 TTL 2.0s + 客户端缓存 0.2s + 轮询一圈）")
    print("       → 但全死之前的每一次都是白打（连接被拒，后端连计数都没留下）")

    print("\n幕 4 n1 重新拉起，端口变了（滚动升级的正常结果）")
    newp = nodes["n1"].boot()
    reg.register("n1", newp)
    print(f"       新端口 {newp}（原来不是这个）")
    time.sleep(0.25)                       # 等客户端缓存过期
    ok, fail, h = burst()
    print(f"       30 次调用：成功 {ok}/{ok + fail}  被打分布 {flat(h)}")
    print("       → 客户端一行没改，新端口自动进入轮询")
    return {"半死失败": 0, "全死失败": 0}


# ------------------------------------------------------------------ V3
class Endpoint:
    __slots__ = ("name", "port", "inflight", "strikes", "ejected_until", "probing")

    def __init__(self, name, port):
        self.name = name
        self.port = port
        self.inflight = 0
        self.strikes = 0
        self.ejected_until = 0.0
        self.probing = False


class ClientLB:
    """V3：注册中心名单 + 客户端被动健康检查 + P2C。

      strike_limit   连续失败多少次才摘（一次抖动不摘）
      eject_seconds  摘多久（有期限才可能回来）
      全员被摘时放一个做半开探测（否则永久黑洞）
    """

    def __init__(self, registry, pull_seconds=0.2, eject_seconds=1.0, strike_limit=2):
        self.reg = registry
        self.pull = pull_seconds
        self.eject_seconds = eject_seconds
        self.strike_limit = strike_limit
        self.eps = []
        self.fetched_at = -1e9
        self.lock = threading.Lock()

    def sync(self, force=False):
        now = time.monotonic()
        if not force and now - self.fetched_at < self.pull:
            return
        roster = dict(self.reg.snapshot())
        with self.lock:
            known = {e.name: e for e in self.eps}
            eps = []
            for name, port in roster.items():
                if name in known:
                    known[name].port = port      # 端口可能变
                    eps.append(known[name])
                else:
                    eps.append(Endpoint(name, port))
            self.eps = eps
            self.fetched_at = now

    def pick(self):
        now = time.monotonic()
        with self.lock:
            if not self.eps:
                raise RuntimeError("no endpoints")
            alive = [e for e in self.eps if e.ejected_until <= now]
            if not alive:
                probe = min(self.eps, key=lambda e: e.ejected_until)
                probe.probing = True
                alive = [probe]
            if len(alive) == 1:
                e = alive[0]
            else:
                a, b = random.sample(alive, 2)
                e = a if a.inflight <= b.inflight else b
            e.inflight += 1
            return e

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
                if ep.probing or ep.strikes >= self.strike_limit:
                    ep.ejected_until = now + self.eject_seconds
                    ep.probing = False

    def healthy_count(self):
        now = time.monotonic()
        return sum(1 for e in self.eps if e.ejected_until <= now)

    def call(self, idempotent=True):
        self.sync()
        ep = self.pick()
        try:
            v = fetch(ep.port)
            self.report(ep, True)
            return v, ep.name
        except Exception:
            self.report(ep, False)
            if not idempotent:
                raise
            # 换一个实例再试：只有幂等接口能这么做
            others = [e for e in self.eps
                      if e is not ep and e.ejected_until <= time.monotonic()]
            if not others:
                raise
            ep2 = self.pick()
            try:
                v = fetch(ep2.port)
                self.report(ep2, True)
                return v, ep2.name
            except Exception:
                self.report(ep2, False)
                raise


def v3_client_lb(reg, nodes):
    banner("V3 客户端 LB + 健康检查：strike=2 摘流，1.0s 后半开探测，P2C 选择")
    lb = ClientLB(reg, eject_seconds=1.0, strike_limit=2)
    lb.sync(force=True)
    print(f"   已知端点 {[e.name for e in lb.eps]}")

    def burst(n=30):
        reset()
        ok = fail = 0
        for _ in range(n):
            try:
                lb.call()
                ok += 1
            except Exception:
                fail += 1
            time.sleep(0.01)
        return ok, fail, snap(ATTEMPTS)

    ok, fail, h = burst()
    print(f"\n幕 1 常态 5 个实例：成功 {ok}/{ok + fail}  被打分布 {flat(h)}"
          f"  健康 {lb.healthy_count()}/{len(lb.eps)}")

    print("\n幕 2 n1 半死：能连上、返回 503，进程还在、心跳照发")
    READY["n1"] = False
    total, fail, ft, att = run_stream(lb.call, 3.0)
    report_stream("3 秒内", total, fail, ft)
    print(f"       健康端点 {lb.healthy_count()}/{len(lb.eps)}"
          f"｜被摘 {[e.name for e in lb.eps if e.ejected_until > time.monotonic()]}")
    print(f"       n1 被白打 {att.get('n1', 0)} 次 ← 对比 V2 的同一场景")
    print("       → 注册中心名单里还有 n1，但客户端自己把它摘了")

    print("\n幕 3 n1 全死：连不上、也不再发心跳")
    nodes["n1"].kill()
    total, fail, ft, att = run_stream(lb.call, 3.0)
    report_stream("3 秒内", total, fail, ft)
    print(f"       n1 被白打 {att.get('n1', 0)} 次")

    print("\n幕 4 n1 以新端口回来（摘除期过后靠半开探测自己回归）")
    newp = nodes["n1"].boot()
    reg.register("n1", newp)
    time.sleep(1.1)                       # 超过 eject_seconds
    ok, fail, h = burst(n=40)
    print(f"       新端口 {newp}")
    print(f"       40 次调用：成功 {ok}/{ok + fail}  健康 {lb.healthy_count()}/{len(lb.eps)}"
          f"  被打分布 {flat(h)}")
    print("       → 没重启客户端、没改配置，它自己回来了")


# ------------------------------------------------------------------ main
def main():
    print("=" * 76)
    print("应用实战 08：实例扩缩容（三段演进，同一套后端，只改客户端）")
    print("=" * 76)

    nodes = {}
    order = []

    def spawn(name):
        n = Node(name, 0)
        nodes[name] = n
        order.append(n)
        return n.boot()

    def scale_out(*names):
        out = {n: spawn(n) for n in names}
        print("\n运维操作：扩容，新起 "
              + "  ".join(f"{n}:{out[n]}" for n in names) + "（共 5 个）")
        return out

    for i in range(1, 4):
        spawn(f"n{i}")
    print("\n初始集群：" + "  ".join(f"{n}:{nodes[n].port}" for n in ("n1", "n2", "n3")))

    v1_hardcoded(nodes, scale_out)
    print("\n扩容后的完整集群："
          + "  ".join(f"{n}:{nodes[n].port}" for n in sorted(nodes)))

    reg = Registry(hb_ttl=2.0)
    for n in nodes:
        reg.register(n, nodes[n].port)
    reg.run_heartbeats()

    v2_registry(reg, nodes)

    # 让 V3 从干净状态开始：n1 已换端口且健康，其余都在
    READY["n1"] = True
    HB_ALIVE.add("n1")
    reg.register("n1", nodes["n1"].port)

    v3_client_lb(reg, nodes)

    for n in order:
        n.kill()


if __name__ == "__main__":
    main()
