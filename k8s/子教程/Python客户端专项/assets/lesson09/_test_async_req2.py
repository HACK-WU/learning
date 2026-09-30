"""课 9：放大样本，把 pool_threads=1 的串行效应逼出来

上一轮 N=8 单请求仅 6ms，线程开销吞掉差异（1.38x，不可信）。
本轮放大：
  - N = 60（更多请求）
  - 每次 list 全量 pods（不加 limit，响应更大 → 单请求耗时更久）
  - 重复 3 轮取中位数
"""
import statistics
import time
from kubernetes import client, config

config.load_kube_config()

N = 60
ROUNDS = 3


def run(api, tag):
    times = []
    for rnd in range(ROUNDS):
        t0 = time.time()
        threads = [api.list_pod_for_all_namespaces(async_req=True)
                   for _ in range(N)]
        results = [t.get() for t in threads]
        el = time.time() - t0
        times.append(el)
        print(f"  {tag} 第{rnd+1}轮: {el:.2f}s (返回{len(results)})")
    return statistics.median(times)


print("=" * 64)
print(f"N={N} 个 async_req 全量 list pods，{ROUNDS} 轮取中位数")
print("=" * 64)

print("\n[默认 pool_threads=1]")
api_default = client.CoreV1Api()
t1 = run(api_default, "默认")

print("\n[显式 pool_threads=16]")
api_16 = client.CoreV1Api(client.ApiClient(pool_threads=16))
t2 = run(api_16, "16线程")

print("\n--- 串行基准：N 个同步请求 ---")
api_s = client.CoreV1Api()
t0 = time.time()
for _ in range(N):
    api_s.list_pod_for_all_namespaces()
t_serial = time.time() - t0
print(f"纯串行 N={N}: {t_serial:.2f}s")

print("\n--- 单请求基准 ---")
t0 = time.time()
api_s.list_pod_for_all_namespaces()
one = time.time() - t0
print(f"1 个请求: {one*1000:.1f}ms")

print()
print("=" * 64)
print(f"串行基准        : {t_serial:.2f}s")
print(f"async_req 默认(1): {t1:.2f}s  -> 相对串行 {t_serial/t1:.2f}x")
print(f"async_req 16线程 : {t2:.2f}s  -> 相对串行 {t_serial/t2:.2f}x")
print(f"16线程 vs 默认   : {t1/t2:.2f}x")
print("=" * 64)
