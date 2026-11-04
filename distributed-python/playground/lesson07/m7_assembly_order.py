"""M7：三件套的装配顺序 —— 同一个"下游挂了 + 流量洪峰"场景，三种装配的差别。

为什么顺序重要：熔断、限流、隔离各自都不解决别人的问题。
  限流   决定"这一秒放进来多少"
  舱壁   决定"放进来之后最多占用多少资源"
  熔断   决定"还要不要继续试"
顺序错了，每一层都会替下一层白干。

三种装配：
  A 只有熔断（无限流、无舱壁）：熔断挡住大部分，但冷启动瞬间与探针仍能压垮下游
  B 熔断在外 + 舱壁在内（无入口限流）：突发瞬间排队，但不会把下游打爆
  C 限流 → 舱壁 → 熔断（标准顺序）：入口就把洪峰削平，下游始终在配额内

观测：下游被打次数、上游排队超时数、成功数。
"""
import threading
import time
import urllib.request

from _downstream import Downstream

CLIENTS = 60                 # 洪峰并发
BUDGET = 0.4
DOWNSTREAM_LIMIT_QPS = 10    # 下游能扛的量
DOWNSTREAM_DELAY = 0.08      # 下游正常处理耗时
BULKHEAD = 6                 # 舱壁容量（可同时在下游飞的请求）
FAIL_THRESHOLD = 5
OPEN_SECONDS = 0.5
T_BURST = 0.7                # 洪峰持续多久
T_TOTAL = 2.2


class TokenBucket:
    def __init__(self, rate, burst=1):
        self.rate, self.burst = rate, burst
        self.tokens = float(burst)
        self.last = None
        self.lock = threading.Lock()

    def allow(self):
        with self.lock:
            now = time.perf_counter()
            if self.last is None:
                self.last = now
            self.tokens = min(self.burst, self.tokens + (now - self.last) * self.rate)
            self.last = now
            if self.tokens >= 1:
                self.tokens -= 1
                return True
            return False


class Breaker:
    def __init__(self, threshold, open_seconds):
        self.threshold, self.open_seconds = threshold, open_seconds
        self.state, self.fails, self.opened_at = "Closed", 0, 0.0
        self.lock = threading.Lock()

    def allow(self):
        with self.lock:
            if self.state == "Open":
                if time.perf_counter() - self.opened_at >= self.open_seconds:
                    self.state = "Half-Open"
                    return True
                return False
            return self.state != "Half-Open"

    def record(self, ok):
        with self.lock:
            if ok:
                if self.state == "Half-Open":
                    self.state = "Closed"
                self.fails = 0
            else:
                if self.state == "Half-Open":
                    self.state = "Open"
                    self.opened_at = time.perf_counter()
                else:
                    self.fails += 1
                    if self.fails >= self.threshold:
                        self.state = "Open"
                        self.opened_at = time.perf_counter()


def run(mode):
    with Downstream(delay=DOWNSTREAM_DELAY) as c:
        gate = threading.BoundedSemaphore(BULKHEAD)
        bucket = TokenBucket(DOWNSTREAM_LIMIT_QPS)
        cb = Breaker(FAIL_THRESHOLD, OPEN_SECONDS) if mode in ("A", "B", "C") else None
        use_bulkhead = mode in ("B", "C")
        use_limit = mode == "C"

        stop = threading.Event()
        lock = threading.Lock()
        stats = {"ok": 0, "limited": 0, "short": 0, "queue": 0, "err": 0}
        t0 = time.perf_counter()

        def clock():
            return time.perf_counter() - t0

        def handle():
            # 装配顺序就是这三行的顺序，这就是"位置"的全部含义
            if use_limit and not bucket.allow():
                return "LIMITED"
            if cb and not cb.allow():
                return "SHORT_CIRCUIT"

            if use_bulkhead:
                if not gate.acquire(timeout=BUDGET):
                    return "QUEUE_TIMEOUT"
            try:
                with urllib.request.urlopen(c.url, timeout=BUDGET) as r:
                    r.read()
                if cb:
                    cb.record(True)
                return "ok"
            except Exception:
                if cb:
                    cb.record(False)
                return "ERR"
            finally:
                if use_bulkhead:
                    gate.release()

        def client():
            while not stop.is_set() and clock() < T_TOTAL:
                if clock() > T_BURST:
                    time.sleep(0.05)
                    # 洪峰过后改为温和流量
                code = handle()
                with lock:
                    key = {"ok": "ok", "LIMITED": "limited",
                           "SHORT_CIRCUIT": "short",
                           "QUEUE_TIMEOUT": "queue"}.get(code, "err")
                    stats[key] += 1
                time.sleep(0.005)

        ts = [threading.Thread(target=client, daemon=True)
              for _ in range(CLIENTS)]
        for t in ts:
            t.start()
        time.sleep(T_TOTAL + 0.5)
        stop.set()
        for t in ts:
            t.join(timeout=2)

        labels = {"A": "A 只有熔断",
                  "B": "B 熔断 + 舱壁（无限流）",
                  "C": "C 限流 → 舱壁 → 熔断"}
        hits = c.hits
        print(f"\n  {labels[mode]}")
        print(f"    结果: 成功 {stats['ok']:>4} ｜ 被限流 {stats['limited']:>4}"
              f" ｜ 熔断短路 {stats['short']:>4} ｜ 排队超时 {stats['queue']:>4}"
              f" ｜ 下游错误 {stats['err']:>4}")
        print(f"    下游被打 {hits:>4} 次 ｜ 平均 {hits/T_TOTAL:>5.1f} QPS"
              f"（配额 {DOWNSTREAM_LIMIT_QPS} QPS）")
        return hits, stats


def main():
    print("=" * 92)
    print(f"{CLIENTS} 个客户端同时压 {T_BURST}s ｜ 下游正常 {int(DOWNSTREAM_DELAY*1000)}ms"
          f" / 配额 {DOWNSTREAM_LIMIT_QPS} QPS ｜ 舱壁 {BULKHEAD}")
    print(f"熔断：连续失败 {FAIL_THRESHOLD} 次跳闸，Open {OPEN_SECONDS}s")

    res = {}
    for m in ("A", "B", "C"):
        print("\n" + "#" * 92)
        res[m] = run(m)
    print("\n" + "#" * 92)

    print("\n对照表：")
    print(f"  {'装配':<24}{'下游被打':>10}{'平均QPS':>10}{'成功':>8}"
          f"{'限流':>8}{'短路':>8}{'排队超时':>10}")
    for m in ("A", "B", "C"):
        hits, st = res[m]
        name = {"A": "只有熔断", "B": "熔断+舱壁", "C": "限流→舱壁→熔断"}[m]
        print(f"  {name:<24}{hits:>10}{hits/T_TOTAL:>10.1f}{st['ok']:>8}"
              f"{st['limited']:>8}{st['short']:>8}{st['queue']:>10}")

    print("\n结论：")
    print("  · 熔断管『还要不要试』，它不削峰；洪峰照旧全部打到下游一次。")
    print("  · 舱壁管『最多占多少资源』，它保护的是自己，不是下游。")
    print("  · 限流管『这一秒放多少进来』，只有它在入口就把量削掉。")
    print("  · 标准顺序：限流（削峰）→ 舱壁（限制占用）→ 熔断（停止徒劳尝试）。")


if __name__ == "__main__":
    main()
