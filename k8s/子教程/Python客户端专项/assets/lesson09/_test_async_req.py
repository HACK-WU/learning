"""课 9：async_req=True 真的并发吗？pool_threads=1 的陷阱

源码线索（api_client.py）：
    def __init__(self, ..., pool_threads=1):
        self.pool_threads = pool_threads
    @property
    def pool(self):
        if self._pool is None:
            self._pool = ThreadPool(self.pool_threads)   # 只有 1 个线程！

async_req=True 时走 self.pool.apply_async —— 池只有 1 线程 → 全部串行
"""
import time
from kubernetes import client, config

config.load_kube_config()

N = 8


def measure(api, tag):
    t0 = time.time()
    threads = [api.list_pod_for_all_namespaces(async_req=True, limit=2)
               for _ in range(N)]
    results = [t.get() for t in threads]
    el = time.time() - t0
    print(f"{tag}: {el:.2f}s  返回 {len(results)} 个结果, "
          f"每个 {[len(r.items) for r in results]}")
    return el


print("=" * 64)
print(f"发起 {N} 个 async_req 请求，测总耗时")
print("=" * 64)

print("\n--- 默认 pool_threads=1 ---")
api_default = client.CoreV1Api()
t1 = measure(api_default, "默认 ApiClient()")

print("\n--- 显式 pool_threads=8 ---")
api_client_8 = client.ApiClient(pool_threads=8)
api_8 = client.CoreV1Api(api_client_8)
t2 = measure(api_8, "ApiClient(pool_threads=8)")

print()
print("=" * 64)
print(f"默认(1线程): {t1:.2f}s")
print(f"显式(8线程): {t2:.2f}s")
print(f"倍数: {t1/t2:.2f}x")
print("=" * 64)

print("\n--- 单个请求基准耗时（串行参考）---")
t0 = time.time()
api_default.list_pod_for_all_namespaces(limit=2)
one = time.time() - t0
print(f"1 个同步请求: {one:.3f}s")
print(f"若真并发，{N} 个应≈{one:.3f}s；若串行，应≈{one*N:.3f}s")
