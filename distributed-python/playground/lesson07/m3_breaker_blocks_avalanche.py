"""M3：熔断挡住的是什么？—— 关键取决于"你怎么定义失败"。

两组对照，同一套代码，只改下游的坏法：
  组 A  下游「快速失败」（返回 503，10ms）  → 熔断器能跳闸
  组 B  下游「慢但最终成功」（1000ms 后 200）→ 熔断器不跳闸（盲区）

每组都跑「无熔断 vs 有熔断」两个场景，时间线一致：
  0.0-0.6s 健康 ｜ 0.6-2.0s 坏 ｜ 2.0s 起恢复

组 B 再补一个变体：把"超过 300ms 也算失败"（慢调用判定）加上去，看能不能跳闸。
"""
import threading
import time
import urllib.request

from _downstream import Downstream

CLIENTS = 20
CLIENT_INTERVAL = 0.02       # 每个客户端两次请求的最小间隔（节流，防短路时空转）
BUDGET = 0.3
B_WORKERS = 8
B_UPSTREAM_TIMEOUT = 5
FAIL_THRESHOLD = 5
OPEN_SECONDS = 0.4
SLOW_CALL_MS = 300          # 慢调用判定线

T_HEALTHY_END = 0.6
T_RECOVER = 2.0
T_TOTAL = 3.6


class Breaker:
    """带慢调用判定的三态熔断器。

    count_slow=False → 只看硬失败（异常 / 5xx），这是大多数朴素实现的做法
    count_slow=True  → 超过 slow_ms 的调用也计为失败（Resilience4j 的 slowCallRate）
    """

    def __init__(self, threshold, open_seconds, count_slow=False, slow_ms=300):
        self.threshold = threshold
        self.open_seconds = open_seconds
        self.count_slow = count_slow
        self.slow_ms = slow_ms
        self.state = "Closed"
        self.fails = 0
        self.opened_at = 0.0
        self.trips = 0
        self.lock = threading.Lock()

    def allow(self):
        with self.lock:
            if self.state == "Open":
                if time.perf_counter() - self.opened_at >= self.open_seconds:
                    self.state = "Half-Open"
                    return True
                return False
            if self.state == "Half-Open":
                return False
            return True

    def record(self, ok, elapsed_ms):
        bad = (not ok) or (self.count_slow and elapsed_ms > self.slow_ms)
        with self.lock:
            if not bad:
                if self.state == "Half-Open":
                    self.state = "Closed"
                self.fails = 0
                return
            if self.state == "Half-Open":
                self.state = "Open"
                self.opened_at = time.perf_counter()
                self.trips += 1
                return
            self.fails += 1
            if self.fails >= self.threshold:
                self.state = "Open"
                self.opened_at = time.perf_counter()
                self.trips += 1


class BService:
    def __init__(self, downstream_url, cb):
        self.url_down = downstream_url
        self.cb = cb
        self.sem = threading.BoundedSemaphore(B_WORKERS)
        self.lock = threading.Lock()
        self.worker_busy_ms = 0.0

    def handle(self, deadline):
        if self.cb and not self.cb.allow():
            return "SHORT_CIRCUIT"

        remain = deadline - time.perf_counter()
        if remain <= 0 or not self.sem.acquire(timeout=remain):
            return "QUEUE_TIMEOUT"

        t0 = time.perf_counter()
        ok = False
        try:
            with urllib.request.urlopen(self.url_down,
                                        timeout=B_UPSTREAM_TIMEOUT) as r:
                r.read()
            ok = True
            return "ok"
        except Exception:
            return "UPSTREAM_ERR"
        finally:
            ms = (time.perf_counter() - t0) * 1000
            with self.lock:
                self.worker_busy_ms += ms
            self.sem.release()
            if self.cb:
                self.cb.record(ok, ms)


def run(bad_mode, breaker_desc, make_cb):
    """bad_mode: 'fast_fail' 或 'slow_ok'"""
    with Downstream(delay=0.02) as c:
        cb = make_cb()
        b = BService(c.url, cb)
        stop = threading.Event()
        lock = threading.Lock()
        buckets = [[0, 0, 0] for _ in range(4)]   # ok / short / other
        t0 = time.perf_counter()
        first_ok_after = [None]

        def clock():
            return time.perf_counter() - t0

        def phase_switch():
            while clock() < T_HEALTHY_END:
                time.sleep(0.01)
            if bad_mode == "fast_fail":
                c.httpd.code = 503
            else:
                c.httpd.delay = 1.0
            while clock() < T_RECOVER:
                time.sleep(0.01)
            c.httpd.code = 200
            c.httpd.delay = 0.02

        def client():
            while not stop.is_set():
                now = clock()
                if now >= T_TOTAL:
                    return
                code = b.handle(time.perf_counter() + BUDGET)
                idx = min(3, int(now))
                with lock:
                    if code == "ok":
                        buckets[idx][0] += 1
                        if now >= T_RECOVER and first_ok_after[0] is None:
                            first_ok_after[0] = now - T_RECOVER
                    elif code == "SHORT_CIRCUIT":
                        buckets[idx][1] += 1
                    else:
                        buckets[idx][2] += 1
                time.sleep(CLIENT_INTERVAL)

        sw = threading.Thread(target=phase_switch, daemon=True)
        cs = [threading.Thread(target=client, daemon=True)
              for _ in range(CLIENTS)]
        sw.start()
        for t in cs:
            t.start()
        time.sleep(T_TOTAL + 0.2)
        stop.set()
        for t in cs:
            t.join(timeout=2)

        short_total = sum(x[1] for x in buckets)
        ok_total = sum(x[0] for x in buckets)
        trips = cb.trips if cb else 0
        rec = ("无" if first_ok_after[0] is None
               else f"+{first_ok_after[0]*1000:.0f} ms")
        print(f"  {breaker_desc:<28} 成功 {ok_total:>4} ｜ 短路 {short_total:>4}"
              f" ｜ 跳闸 {trips:>2} 次 ｜ 恢复后首次成功 {rec:>10}"
              f" ｜ 下游被打 {c.hits:>3} ｜ worker {b.worker_busy_ms:>6.0f} ms·次")
        return dict(ok=ok_total, short=short_total, trips=trips,
                    rec=first_ok_after[0], hits=c.hits,
                    busy=b.worker_busy_ms)


def main():
    print("=" * 100)
    print(f"客户端 {CLIENTS} 并发持续打 ｜ B 有 {B_WORKERS} 个 worker ｜ "
          f"每请求预算 {int(BUDGET*1000)}ms")
    print(f"时间线：0-{T_HEALTHY_END}s 健康 ｜ {T_HEALTHY_END}-{T_RECOVER}s 坏 ｜ "
          f"{T_RECOVER}s 起恢复")
    print(f"熔断参数：连续失败 {FAIL_THRESHOLD} 次跳闸，Open {OPEN_SECONDS}s")

    print("\n" + "#" * 100)
    print("# 组 A：下游「快速失败」（返回 503，约 10ms）")
    print("#" * 100)
    run("fast_fail", "无熔断", lambda: None)
    run("fast_fail", "有熔断（只算硬失败）",
        lambda: Breaker(FAIL_THRESHOLD, OPEN_SECONDS))

    print("\n" + "#" * 100)
    print("# 组 B：下游「慢但最终成功」（1000ms 后返回 200）")
    print("#" * 100)
    run("slow_ok", "无熔断", lambda: None)
    run("slow_ok", "有熔断（只算硬失败）",
        lambda: Breaker(FAIL_THRESHOLD, OPEN_SECONDS))
    run("slow_ok", f"有熔断（慢 >{SLOW_CALL_MS}ms 也算失败）",
        lambda: Breaker(FAIL_THRESHOLD, OPEN_SECONDS,
                        count_slow=True, slow_ms=SLOW_CALL_MS))

    print("\n" + "=" * 100)
    print("结论一：熔断器只对『它认得的失败』有反应。下游快速 503 → 能跳闸；")
    print("        下游只是慢、最后还成功了 → 只算硬失败的熔断器完全不跳（组 B 第 2 行）。")
    print("结论二：所以「什么算失败」必须显式定义——异常、5xx，以及『超过 N ms 的慢调用』。")
    print("        加上慢调用判定后，慢下游才真正能被熔断挡在门外（组 B 第 3 行）。")


if __name__ == "__main__":
    main()
