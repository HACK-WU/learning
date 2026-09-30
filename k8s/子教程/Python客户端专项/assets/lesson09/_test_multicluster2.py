"""修正：多集群并发测法的三个问题

问题 1: 每次 scan_cluster 都 new_client_from_config（含文件 IO + 建连接），
        这段 CPU/IO 开销把并发收益吃掉了 → 应复用 client，只测请求并发
问题 2: 耗时仅 0.05s 量级，噪声占主导 → 应放大 N 倍
问题 3: 串行/并发各只跑 1 次 → 应多轮取中位数

修正后重测。
"""
import asyncio
import statistics
import time

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

CONTEXTS = ["kind-k8s-c1", "kind-otel-l11"]
ROUNDS = 5
REPEAT = 5   # 每个集群重复查几次，放大样本


async def build_clients():
    clients = {}
    for c in CONTEXTS:
        ac = await ka.config.new_client_from_config(context=c)
        clients[c] = ac
    return clients


async def query_once(v1, kind):
    if kind == "pods":
        r = await v1.list_pod_for_all_namespaces()
    elif kind == "ns":
        r = await v1.list_namespace()
    elif kind == "svc":
        r = await v1.list_service_for_all_namespaces()
    else:
        r = await v1.list_config_map_for_all_namespaces()
    return len(r.items)


async def main():
    clients = await build_clients()
    apis = {c: CoreV1Api(ac) for c, ac in clients.items()}
    resources = ["pods", "ns", "svc", "cm"]

    print("=" * 70)
    print(f"修正后：client 复用 + {ROUNDS} 轮取中位数 + 每轮 {REPEAT} 次查询")
    print("=" * 70)

    # 预热
    for c, v1 in apis.items():
        await query_once(v1, "pods")
    print("  [预热完成]\n")

    # 串行：逐个集群、逐个资源、逐个 repeat
    serial_times = []
    for _ in range(ROUNDS):
        t0 = time.time()
        for c in CONTEXTS:
            v1 = apis[c]
            for k in resources:
                for _r in range(REPEAT):
                    await query_once(v1, k)
        serial_times.append(time.time() - t0)
    t_serial = statistics.median(serial_times)
    print(f"  串行: {t_serial:.3f}s  (各轮 {[f'{x:.3f}' for x in serial_times]})")

    # 并发：所有请求一起 gather
    conc_times = []
    for _ in range(ROUNDS):
        tasks = []
        for c in CONTEXTS:
            v1 = apis[c]
            for k in resources:
                for _r in range(REPEAT):
                    tasks.append(query_once(v1, k))
        t0 = time.time()
        await asyncio.gather(*tasks)
        conc_times.append(time.time() - t0)
    t_conc = statistics.median(conc_times)
    print(f"  并发: {t_conc:.3f}s  (各轮 {[f'{x:.3f}' for x in conc_times]})")

    total_req = len(CONTEXTS) * len(resources) * REPEAT
    print(f"\n  总请求数: {total_req}")
    print(f"  >>> 加速比: {t_serial/t_conc:.2f}x")

    print()
    print("=" * 70)
    print("对照：raw 模式（不反序列化）的加速比")
    print("=" * 70)

    async def query_raw(v1, kind):
        fn = {
            "pods": v1.list_pod_for_all_namespaces,
            "ns": v1.list_namespace,
            "svc": v1.list_service_for_all_namespaces,
            "cm": v1.list_config_map_for_all_namespaces,
        }[kind]
        r = await fn(_preload_content=False)
        data = await r.read()
        return len(data)

    for c, v1 in apis.items():
        await query_raw(v1, "pods")

    s_times = []
    for _ in range(ROUNDS):
        t0 = time.time()
        for c in CONTEXTS:
            v1 = apis[c]
            for k in resources:
                for _r in range(REPEAT):
                    await query_raw(v1, k)
        s_times.append(time.time() - t0)
    t_raw_s = statistics.median(s_times)

    c_times = []
    for _ in range(ROUNDS):
        tasks = [query_raw(apis[c], k)
                 for c in CONTEXTS for k in resources for _r in range(REPEAT)]
        t0 = time.time()
        await asyncio.gather(*tasks)
        c_times.append(time.time() - t0)
    t_raw_c = statistics.median(c_times)

    print(f"  raw 串行: {t_raw_s:.3f}s")
    print(f"  raw 并发: {t_raw_c:.3f}s")
    print(f"  >>> 加速比: {t_raw_s/t_raw_c:.2f}x")

    print()
    print("=" * 70)
    print("汇总")
    print("=" * 70)
    print(f"  含反序列化 并发加速: {t_serial/t_conc:.2f}x")
    print(f"  纯 HTTP     并发加速: {t_raw_s/t_raw_c:.2f}x")
    print("  （差异 = 反序列化这部分 CPU 无法并行）")

    for ac in clients.values():
        await ac.close()


asyncio.run(main())
