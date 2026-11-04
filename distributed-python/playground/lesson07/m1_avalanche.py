"""M1：雪崩是怎么发生的 —— 慢下游如何把上游自己的 worker 全部占死。

拓扑：
    A（客户端，50 并发，总预算 300ms）
      → B（上游服务，固定 8 个 worker，队列无上限，自己调下游不设超时）
        → C（下游服务，真实的本地 HTTP 服务，延迟可调）

三个观测点：
  1. A 视角：成功 / 排队超时 / 上游调用超时
  2. C 实际被打几次（幽灵请求：A 早走了，C 还在被打）
  3. B 的峰值排队深度（worker 全占后，新请求只能排队）

为什么 B 调 C 不设短超时：这正是雪崩的真实成因——上游「忘了」给下游设超时，
以为靠调用方的超时兜着就行。于是调用方走了，B 的 worker 还在替下游等。
"""
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, wait

from _downstream import Downstream, pct

A_CONCURRENCY = 50
A_BUDGET = 0.3          # A 的总预算（不是每层各 300ms）
B_WORKERS = 8
B_UPSTREAM_TIMEOUT = 5  # B 调下游几乎不设超时：雪崩的技术前提


class BService:
    def __init__(self, downstream_url, workers=B_WORKERS):
        self.url_down = downstream_url
        self.sem = threading.BoundedSemaphore(workers)
        self.lock = threading.Lock()
        self.inflight = 0
        self.peak_waiting = 0
        self.stats = {"ok": 0, "queue_timeout": 0,
                      "upstream_timeout": 0, "upstream_hit": 0}

    def reset(self):
        with self.lock:
            self.peak_waiting = 0
            self.stats = {"ok": 0, "queue_timeout": 0,
                          "upstream_timeout": 0, "upstream_hit": 0}

    def handle(self, deadline):
        with self.lock:
            self.inflight += 1
            self.peak_waiting = max(self.peak_waiting, self.inflight - B_WORKERS)
        got = False
        try:
            remain = deadline - time.perf_counter()
            if remain <= 0 or not self.sem.acquire(timeout=remain):
                with self.lock:
                    self.stats["queue_timeout"] += 1
                return "QUEUE_TIMEOUT"     # 连 worker 都没拿到，下游一次没被打
            got = True
            with self.lock:
                self.stats["upstream_hit"] += 1
            with urllib.request.urlopen(self.url_down,
                                        timeout=B_UPSTREAM_TIMEOUT) as r:
                r.read()
            with self.lock:
                self.stats["ok"] += 1
            return "ok"
        except Exception:
            with self.lock:
                self.stats["upstream_timeout"] += 1
            return "UPSTREAM_TIMEOUT"      # 打到了下游，但没等到结果
        finally:
            if got:
                self.sem.release()
            with self.lock:
                self.inflight -= 1


def a_round(b, n=A_CONCURRENCY, budget=A_BUDGET):
    """A 侧一轮：所有请求共享同一个截止时刻（总预算），各自记结果。"""
    deadline = time.perf_counter() + budget
    lat, codes = [], {}
    lock = threading.Lock()

    def call():
        t0 = time.perf_counter()
        code = b.handle(deadline)
        d = time.perf_counter() - t0
        with lock:
            lat.append(d)
            codes[code] = codes.get(code, 0) + 1

    pool = ThreadPoolExecutor(max_workers=n)
    futs = [pool.submit(call) for _ in range(n)]
    wait(futs, timeout=budget + 0.05)      # 只在预算内等，不等后台残留
    pool.shutdown(wait=False)
    return lat, codes


def show(tag, lat, codes, ds, b, hits_before):
    print(f"\n{tag}")
    print(f"  A 结果      : {codes or '{}'}")
    print(f"  A P50/P99   : {pct(lat,50)*1000:.0f} ms / {pct(lat,99)*1000:.0f} ms")
    print(f"  C 被打      : {ds.hits - hits_before} 次")
    print(f"  B 峰值排队  : {b.peak_waiting} 个（worker 数 = {B_WORKERS}）")


def main():
    with Downstream(delay=0.02) as c:
        b = BService(c.url)
        print("=" * 66)
        print(f"A: {A_CONCURRENCY} 并发 / 总预算 {int(A_BUDGET*1000)}ms ｜ "
              f"B: {B_WORKERS} worker ｜ C: 真实下游")
        print(f"B 调 C 的超时: {B_UPSTREAM_TIMEOUT}s（≈ 没设超时）")

        h = c.hits
        lat, codes = a_round(b)
        show("R1 下游健康（20ms）", lat, codes, c, b, h)
        print("  → 8 个 worker 应付 50 并发：靠排队，A 在预算内都等到了")

        print("\n" + "=" * 66)
        print("R2 下游卡住（1000ms）")
        c.httpd.delay = 1.0
        b.reset()
        h = c.hits
        lat, codes = a_round(b)
        show("R2 下游卡住", lat, codes, c, b, h)
        print(f"  → 打下游 {c.hits - h} 次，A 拿到有用结果 0 次；"
              f"其余 {b.stats['queue_timeout']} 个请求连下游都没碰到就死了")

        print("\n" + "=" * 66)
        print("R3 下游已恢复（20ms）—— 但 B 的 8 个 worker 还卡在 R2 的下游调用上")
        c.httpd.delay = 0.02
        b.reset()
        h = c.hits
        lat, codes = a_round(b)
        show("R3 下游已恢复", lat, codes, c, b, h)
        print(f"  → C 这次只被打 {c.hits - h} 次，A 依然全灭："
              f"雪崩的余波在 B 自己身上")

    print("\n" + "=" * 66)
    print("结论：下游变慢本身不致命；致命的是上游用『还在替下游等』的 worker 去接新请求。")


if __name__ == "__main__":
    main()
