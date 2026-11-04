"""M6：注册中心列表过期时，客户端会用旧地址继续打已摘流的实例。

真实形态：readiness 探针失败 → endpoint 开始摘除 → 传播到每个客户端需要时间。
在这段窗口里，实例还活着、还在收流量，只是每个请求都返回 503。

为了不让"实例下线"这件事本身吃掉观察窗口，本脚本不真关进程，
而是让 n3 保持监听、但业务直接返回 503。

纯标准库。
"""
import random
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HITS = {}
SERVED = {}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    sid = "?"
    healthy = True

    def do_GET(self):
        with LOCK:
            HITS[self.sid] = HITS.get(self.sid, 0) + 1
            SERVED[self.sid] = SERVED.get(self.sid, 0) + 1
        if self.healthy:
            body = self.sid.encode()
            self.send_response(200)
        else:
            body = b"not ready"
            self.send_response(503)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def start(sid, healthy):
    h = type(f"H_{sid}", (Handler,), {"sid": sid, "healthy": healthy})
    srv = ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


class Registry:
    """带缓存的注册中心：客户端拿到的列表最多 ttl 秒前生成。"""

    def __init__(self, ttl_ms):
        self.ttl = ttl_ms / 1000.0
        self.alive = {}
        self._cache = None
        self._cache_at = -1e9

    def register(self, sid, port):
        self.alive[sid] = port

    def deregister(self, sid):
        self.alive.pop(sid, None)

    def endpoints(self):
        now = time.monotonic()
        if self._cache is not None and now - self._cache_at < self.ttl:
            return list(self._cache)
        self._cache = list(self.alive.values())
        self._cache_at = now
        return list(self._cache)


def fetch(port, timeout=0.3):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=timeout) as r:
        return r.read().decode()


def run(mode, ttl_ms=800, n=200, interval=0.010, seed=7):
    """mode: plain(只信列表) / retry(失败重试别的实例) / probe(连续失败剔除)"""
    random.seed(seed)
    HITS.clear()
    SERVED.clear()

    reg = Registry(ttl_ms=ttl_ms)
    srvs, ports = {}, {}
    for sid in ["n1", "n2"]:
        srv, p = start(sid, healthy=True)
        srvs[sid], ports[sid] = srv, p
        reg.register(sid, p)
    srv3, p3 = start("n3", healthy=False)      # 已摘流：返回 503
    srvs["n3"], ports["n3"] = srv3, p3
    reg.register("n3", p3)

    reg.endpoints()                             # 预热缓存（最坏情况）
    reg.deregister("n3")                        # t=0 摘流

    dead = p3
    strike = {}
    ok = 0
    hits_dead = 0
    t0 = time.monotonic()
    result = []

    for _ in range(n):
        eps = reg.endpoints()
        if mode == "probe":
            eps = [p for p in eps if strike.get(p, 0) < 2] or eps
        port = random.choice(eps)
        if port == dead:
            hits_dead += 1
        success = False
        try:
            fetch(port)
            success = True
            strike[port] = 0
        except Exception:
            strike[port] = strike.get(port, 0) + 1
            if mode in ("retry", "probe"):
                others = [p for p in eps if p != port and strike.get(p, 0) < 2]
                if others:
                    try:
                        fetch(random.choice(others))
                        success = True
                    except Exception:
                        pass
        if success:
            ok += 1
        result.append((success, port == dead, time.monotonic() - t0))
        time.sleep(interval)

    for srv in srvs.values():
        srv.shutdown()
        srv.server_close()

    in_window = [r for r in result if r[2] <= ttl_ms / 1000.0]
    return {
        "ok": ok,
        "total": n,
        "hits_dead": hits_dead,
        "win_total": len(in_window),
        "win_fail": sum(1 for r in in_window if not r[0]),
        "after_fail": sum(1 for r in result if r[2] > ttl_ms / 1000.0 and not r[0]),
    }


print("=" * 78)
print("M6：注册中心列表过期 → 客户端继续打已摘流的实例（实例返回 503）")
print("=" * 78)
print("3 个实例，t=0 时 n3 摘流并返回 503；列表 TTL 800ms；200 个请求 @10ms\n")

rows = []
for mode, label in [
    ("plain", "① 只信列表"),
    ("retry", "② 失败重试到别的实例"),
    ("probe", "③ 列表 + 客户端剔除"),
]:
    r = run(mode)
    rows.append((label, r))
    print(f"【{label}】")
    print(f"  成功率        : {r['ok']}/{r['total']} = {r['ok']/r['total']*100:5.1f}%")
    print(f"  打到 n3 的次数 : {r['hits_dead']}")
    print(f"  过期窗口内 {r['win_total']:3d} 个请求 → 失败 {r['win_fail']:3d}")
    print(f"  窗口过后失败   : {r['after_fail']}")
    print()

print("""
判读：
  · 只有落在"列表 TTL 窗口"内的请求可能打到 n3。窗口一过列表刷新，n3 自然消失。
    所以这个问题的规模 = 摘流频率 × 列表 TTL × 命中的比例
  · ① 只信列表：窗口内打到 n3 的请求全失败，用户直接看到 503
  · ② 重试到别的实例：窗口内的失败被掩盖，用户无感（前提：接口幂等，见课 6）
  · ③ 客户端剔除：不打第二次，但"连续 N 次才剔除"是必须的，
    否则一次抖动就踢掉健康实例，反而制造故障
  · 两条路要一起收紧：TTL 调小让窗口变短，客户端容忍单次失败（重试或剔除）
""")
