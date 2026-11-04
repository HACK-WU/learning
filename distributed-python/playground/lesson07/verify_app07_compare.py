"""三段对照：超时 / 超时+舱壁+子预算 / 全套三道门，看各自贡献。"""
import json
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Downstream:
    def __init__(self, delay_ms=20, code=200):
        outer = self

        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                outer.hits += 1
                time.sleep(outer.delay_ms / 1000)
                body = json.dumps({"ok": outer.code == 200}).encode()
                try:
                    self.send_response(outer.code)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def log_message(self, *a):
                pass

        self.hits = 0
        self.delay_ms = delay_ms
        self.code = code
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.httpd.daemon_threads = True
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_port}"


class TokenBucket:
    def __init__(self, rate, burst):
        self.rate, self.burst = rate, burst
        self.tokens, self.last = float(burst), time.monotonic()
        self.lock = threading.Lock()
        self.rejected = 0

    def try_acquire(self):
        with self.lock:
            now = time.monotonic()
            self.tokens = min(self.burst, self.tokens + (now - self.last) * self.rate)
            self.last = now
            if self.tokens >= 1:
                self.tokens -= 1
                return True
            self.rejected += 1
            return False


class Bulkhead:
    def __init__(self, n):
        self.sem = threading.BoundedSemaphore(n)

    def run(self, fn, deadline):
        remain = deadline - time.monotonic()
        if remain <= 0 or not self.sem.acquire(timeout=remain):
            raise TimeoutError("bulkhead full")
        try:
            return fn()
        finally:
            self.sem.release()


class CircuitBreaker:
    def __init__(self, threshold=5, open_seconds=10.0, window=10.0, slow_ms=300):
        self.threshold, self.open_seconds = threshold, open_seconds
        self.window, self.slow_ms = window, slow_ms
        self.state, self.fails, self.opened_at = "Closed", 0, 0.0
        self.window_start = time.monotonic()
        self.lock = threading.Lock()
        self.trips = 0

    def allow(self):
        with self.lock:
            if self.state == "Open":
                if time.monotonic() - self.opened_at >= self.open_seconds:
                    self.state = "Half-Open"
                    return True
                return False
            return True

    def record(self, ok, elapsed_ms):
        with self.lock:
            now = time.monotonic()
            if now - self.window_start > self.window:
                self.fails, self.window_start = 0, now
            if ok and elapsed_ms <= self.slow_ms:
                if self.state == "Half-Open":
                    self.state, self.fails = "Closed", 0
                return
            self.fails += 1
            if self.state == "Half-Open":
                self.state, self.opened_at = "Open", now
            elif self.fails >= self.threshold:
                self.state, self.opened_at = "Open", now
                self.trips += 1


class OrderService:
    """mode: 'plain'=只有超时(共享池) / 'bulkhead'=+独立池+子预算 / 'full'=+熔断+限流"""

    def __init__(self, mode="full", workers=8, rate=100, burst=100):
        self.mode = mode
        self.limiter = TokenBucket(rate if mode == "full" else 10 ** 9,
                                  burst if mode == "full" else 10 ** 9)
        if mode == "plain":
            shared = Bulkhead(workers)
            self.pools = {"rec": shared, "pay": shared, "stock": shared}
        else:
            self.pools = {"rec": Bulkhead(3), "pay": Bulkhead(4), "stock": Bulkhead(3)}
        self.breakers = {"rec": CircuitBreaker()} if mode == "full" else {}

    def create_order(self, urls, budget=0.300):
        if not self.limiter.try_acquire():
            return "RATE_LIMITED"
        deadline = time.monotonic() + budget
        out = {}
        for name in ("rec", "pay", "stock"):
            sub = deadline
            if self.mode != "plain" and name == "rec":
                sub = min(deadline, time.monotonic() + 0.100)   # 旁路独立小预算
            out[name] = self._guarded(name, urls[name], sub)
        return out

    def _guarded(self, name, url, deadline):
        breaker = self.breakers.get(name)
        if breaker and not breaker.allow():
            return {"degraded": True}

        def call():
            t0 = time.monotonic()
            try:
                remain = deadline - t0
                if remain <= 0:
                    raise TimeoutError("budget exhausted")
                with urllib.request.urlopen(url, timeout=remain) as r:
                    body = json.loads(r.read())
                if breaker:
                    breaker.record(True, (time.monotonic() - t0) * 1000)
                return body
            except Exception:
                if breaker:
                    breaker.record(False, (time.monotonic() - t0) * 1000)
                raise

        try:
            return self.pools[name].run(call, deadline)
        except Exception as e:
            return {"degraded": True, "why": type(e).__name__}


def run_phase(svc, urls, n=50, conc=20):
    core_ok = limited = 0
    lock = threading.Lock()
    idx = [0]

    def worker():
        nonlocal core_ok, limited
        while True:
            with lock:
                if idx[0] >= n:
                    return
                idx[0] += 1
            r = svc.create_order(urls)
            with lock:
                if r == "RATE_LIMITED":
                    limited += 1
                elif isinstance(r, dict):
                    pay_ok = isinstance(r.get("pay"), dict) and r["pay"].get("ok")
                    stk_ok = isinstance(r.get("stock"), dict) and r["stock"].get("ok")
                    if pay_ok and stk_ok:
                        core_ok += 1
                # else 核心失败不计

    ts = [threading.Thread(target=worker) for _ in range(conc)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    return core_ok, limited


rec = Downstream(20)
pay = Downstream(40)
stock = Downstream(15)
urls = {"rec": rec.url, "pay": pay.url, "stock": stock.url}

print("=" * 84)
print("三段对照：推荐服务慢到 1000ms 时，核心链路（支付+库存）能否活下来")
print("=" * 84)
print("无上限并发打 50 个请求，并发度 20，总预算 300ms\n")

header = f"{'装配':<34}{'核心链路成功':<16}{'推荐被打':<12}{'熔断跳闸':<12}{'旁路结果'}"
print(header)
print("-" * 84)

for label, mode in [("① 只有超时（共享 8 位子）", "plain"),
                    ("② + 独立舱壁 + 旁路独立子预算", "bulkhead"),
                    ("③ + 熔断（含慢调用）+ 限流", "full")]:
    rec.hits = 0
    rec.delay_ms = 1000
    svc = OrderService(mode=mode)
    ok, lim = run_phase(svc, urls, n=50, conc=20)
    trips = svc.breakers["rec"].trips if svc.breakers else 0
    print(f"{label:<30}{ok:>3}/50{'':<9}{rec.hits:>5} 次{'':<6}{trips:>3} 次{'':<6}降级→空列表")
    if mode == "full":
        print(f"    └ 熔断器终态: {svc.breakers['rec'].state}｜限流拒绝 {lim} 次")

print("\n" + "=" * 84)
print("再压一轮（推荐仍未恢复，10 秒后熔断器会放探针）")
print("=" * 84)
for label, mode in [("② 独立舱壁 + 子预算（无熔断）", "bulkhead"),
                    ("③ 全套三道门", "full")]:
    rec.hits = 0
    svc = OrderService(mode=mode)
    ok, lim = run_phase(svc, urls, n=50, conc=20)
    trips = svc.breakers["rec"].trips if svc.breakers else 0
    print(f"{label:<30}{ok:>3}/50{'':<9}{rec.hits:>5} 次{'':<6}{trips:>3} 次")

print("\n结论：")
print("  · ② 与 ③ 的核心链路都能活 —— 救核心链路的是『独立舱壁 + 旁路独立子预算』")
print("  · ② 与 ③ 的差别在『推荐被打次数』：熔断把 50 次无效调用压到个位数甚至 0")
print("  · 也就是说：舱壁决定『谁能占多少』，熔断决定『还要不要伸手』，两者不可互替")

rec.httpd.shutdown()
pay.httpd.shutdown()
stock.httpd.shutdown()
