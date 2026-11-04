"""M5：舱壁隔离 —— 一个慢依赖会不会拖死其它不相关的请求。

场景：一个 B 服务对外提供 4 个接口，其中 /search 依赖一个慢下游。
对照两种实现：
  无隔离  ：所有接口共用同一个 8 worker 线程池
  有隔离  ：/search 独占 3 个 worker，其它接口用剩下的池子（舱壁）

观测：/order（与 /search 完全无关、且不依赖任何下游）的可用性。
     —— 这就是"隔离"的全部意义：一个舱进水，船不沉。
"""
import threading
import time
import urllib.request

from _downstream import Downstream, pct

TOTAL_WORKERS = 8
SEARCH_WORKERS = 3
CLIENTS = 30
CLIENT_INTERVAL = 0.01
BUDGET = 0.3
TOTAL_RUN = 2.4
SLOW_START = 0.6
SLOW_DELAY = 1.0


class Bulkhead:
    """普通信号量实现（进程内）。生产里可能是独立线程池 / 独立连接池。"""

    def __init__(self, n):
        self.sem = threading.BoundedSemaphore(n)

    def acquire(self, timeout):
        return self.sem.acquire(timeout=timeout)

    def release(self):
        self.sem.release()


class SharedPool:
    def __init__(self, n):
        self.sem = threading.BoundedSemaphore(n)

    def acquire(self, timeout):
        return self.sem.acquire(timeout=timeout)

    def release(self):
        self.sem.release()


def run_bench(isolated):
    with Downstream(delay=0.02) as c:
        # ---- 池子分配 ----
        if isolated:
            search_bh = Bulkhead(SEARCH_WORKERS)
            order_bh = Bulkhead(TOTAL_WORKERS - SEARCH_WORKERS)
        else:
            shared = SharedPool(TOTAL_WORKERS)
            search_bh = order_bh = shared

        stats = {"search_ok": 0, "search_fail": 0,
                 "order_ok": 0, "order_fail": 0}
        order_lat = []
        lock = threading.Lock()
        stop = threading.Event()
        t0 = time.perf_counter()

        def clock():
            return time.perf_counter() - t0

        def do_search(deadline):
            remain = deadline - time.perf_counter()
            if remain <= 0 or not search_bh.acquire(remain):
                return "QUEUE_TIMEOUT"
            try:
                with urllib.request.urlopen(c.url, timeout=5) as r:
                    r.read()
                return "ok"
            except Exception:
                return "ERR"
            finally:
                search_bh.release()

        def do_order(deadline):
            """不依赖任何下游：只是本地算一下。"""
            remain = deadline - time.perf_counter()
            if remain <= 0 or not order_bh.acquire(remain):
                return "QUEUE_TIMEOUT"
            try:
                time.sleep(0.005)               # 本地干 5ms 活
                return "ok"
            finally:
                order_bh.release()

        def phase():
            while clock() < SLOW_START:
                time.sleep(0.01)
            c.httpd.delay = SLOW_DELAY

        def search_client():
            while not stop.is_set() and clock() < TOTAL_RUN:
                r = do_search(time.perf_counter() + BUDGET)
                with lock:
                    stats["search_ok" if r == "ok" else "search_fail"] += 1
                time.sleep(CLIENT_INTERVAL)

        def order_client():
            while not stop.is_set() and clock() < TOTAL_RUN:
                t = time.perf_counter()
                r = do_order(t + BUDGET)
                d = (time.perf_counter() - t) * 1000
                with lock:
                    if r == "ok":
                        stats["order_ok"] += 1
                        order_lat.append(d)
                    else:
                        stats["order_fail"] += 1
                        order_lat.append(BUDGET * 1000)
                time.sleep(CLIENT_INTERVAL)

        ph = threading.Thread(target=phase, daemon=True)
        ts = ([threading.Thread(target=search_client, daemon=True)
               for _ in range(CLIENTS // 2)] +
              [threading.Thread(target=order_client, daemon=True)
               for _ in range(CLIENTS // 2)])
        ph.start()
        for t in ts:
            t.start()
        time.sleep(TOTAL_RUN + 0.3)
        stop.set()
        for t in ts:
            t.join(timeout=2)

        label = "有舱壁（/search 独占 3）" if isolated else \
                f"无舱壁（共用 {TOTAL_WORKERS}）"
        total_order = stats["order_ok"] + stats["order_fail"]
        ok_rate = stats["order_ok"] / total_order * 100 if total_order else 0
        print(f"\n  {label}")
        print(f"    /search  : 成功 {stats['search_ok']:>3} ｜ 失败 {stats['search_fail']:>3}")
        print(f"    /order   : 成功 {stats['order_ok']:>3} ｜ 失败 {stats['order_fail']:>3}"
              f"  ｜ 成功率 {ok_rate:>5.1f}%")
        print(f"    /order 耗时 P50/P99 : {pct(order_lat,50):.0f} / {pct(order_lat,99):.0f} ms")
        return ok_rate, pct(order_lat, 99)


def main():
    print("=" * 84)
    print(f"B 服务：8 个 worker ｜ 客户端 {CLIENTS} 个（一半打 /search 一半打 /order）")
    print(f"/search 依赖的下游在 {SLOW_START}s 之后变成 {int(SLOW_DELAY*1000)}ms 慢")
    print(f"/order 完全不依赖下游，本地只干 5ms")
    print("\n问题：/search 慢，会不会把 /order 一起拖死？")

    print("\n" + "#" * 84)
    print("# 对照一：无舱壁")
    print("#" * 84)
    ok1, p1 = run_bench(isolated=False)

    print("\n" + "#" * 84)
    print("# 对照二：有舱壁")
    print("#" * 84)
    ok2, p2 = run_bench(isolated=True)

    print("\n" + "=" * 84)
    print("对照：")
    print(f"  /order 成功率   无舱壁 {ok1:>5.1f}%  →  有舱壁 {ok2:>5.1f}%")
    print(f"  /order P99      无舱壁 {p1:>5.0f} ms →  有舱壁 {p2:>5.0f} ms")
    print("\n结论：隔离不提升任何单次调用的性能，它保证的是『一个依赖坏掉时，")
    print("      不依赖它的功能仍然可用』——这是可用性设计，不是性能优化。")


if __name__ == "__main__":
    main()
