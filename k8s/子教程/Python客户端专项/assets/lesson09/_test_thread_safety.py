"""课 9 知识点：同步 client 是否线程安全？

验证目标：
1. 多线程共享一个 ApiClient / CoreV1Api 会不会出错
2. 每线程独立 ApiClient 是否安全
3. 对比两种方式的耗时

前置：同步库 kubernetes 34.1.0（不需要 asyncio）
"""
import threading
import time
import concurrent.futures
from kubernetes import client, config

config.load_kube_config()

results = {}
errors = []


def worker(shared_api, tid):
    """共享 api 对象，反复 list"""
    local = []
    try:
        for i in range(5):
            r = shared_api.list_pod_for_all_namespaces(limit=3)
            local.append(len(r.items))
        results[tid] = local
    except Exception as e:
        errors.append((tid, type(e).__name__, str(e)[:200]))


def worker_own(tid):
    """每线程独立 ApiClient"""
    local = []
    try:
        cfg = client.Configuration()
        config.load_kube_config(client_configuration=cfg)
        api = client.CoreV1Api(client.ApiClient(cfg))
        for i in range(5):
            r = api.list_pod_for_all_namespaces(limit=3)
            local.append(len(r.items))
        results[tid] = local
    except Exception as e:
        errors.append((tid, type(e).__name__, str(e)[:200]))


print("=" * 60)
print("实验 A：10 线程共享同一个 CoreV1Api 实例")
print("=" * 60)
results.clear()
errors.clear()
shared_api = client.CoreV1Api()
t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as ex:
    for tid in range(10):
        ex.submit(worker, shared_api, tid)
t_shared = time.time() - t0
print(f"耗时: {t_shared:.2f}s")
print(f"成功线程: {len(results)}/10")
print(f"错误数: {len(errors)}")
for e in errors[:5]:
    print(f"  [{e[0]}] {e[1]}: {e[2]}")

print()
print("=" * 60)
print("实验 B：10 线程各自独立 ApiClient")
print("=" * 60)
results.clear()
errors.clear()
t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as ex:
    for tid in range(10):
        ex.submit(worker_own, tid)
t_own = time.time() - t0
print(f"耗时: {t_own:.2f}s")
print(f"成功线程: {len(results)}/10")
print(f"错误数: {len(errors)}")
for e in errors[:5]:
    print(f"  [{e[0]}] {e[1]}: {e[2]}")

print()
print("=" * 60)
print(f"共享耗时 {t_shared:.2f}s  vs  独立耗时 {t_own:.2f}s")
print("=" * 60)
