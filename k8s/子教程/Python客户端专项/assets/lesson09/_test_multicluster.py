"""课 9 实战：asyncio.gather + 信号量 并发遍历多集群/多资源

真实场景：有 N 个集群，要同时巡检。
  - 单集群内多资源并发
  - 多集群并发（每集群独立 Configuration —— 课 4 知识点在异步下的形态）
  - 信号量限流：不打爆 apiserver

本机可用：kind-k8s-c1 (5ns/10pods)、kind-otel-l11 (8ns/23pods)
"""
import asyncio
import time

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

CONTEXTS = ["kind-k8s-c1", "kind-otel-l11"]


async def make_client(context):
    """异步下多集群：new_client_from_config 是协程"""
    return await ka.config.new_client_from_config(context=context)


async def scan_cluster(context, resources, sem):
    """扫描单个集群的多个资源"""
    api_client = await make_client(context)
    async with api_client:
        v1 = CoreV1Api(api_client)

        async def get(kind):
            async with sem:
                t0 = time.time()
                try:
                    if kind == "pods":
                        r = await v1.list_pod_for_all_namespaces()
                    elif kind == "ns":
                        r = await v1.list_namespace()
                    elif kind == "svc":
                        r = await v1.list_service_for_all_namespaces()
                    elif kind == "cm":
                        r = await v1.list_config_map_for_all_namespaces()
                    n = len(r.items)
                    return kind, n, None, time.time() - t0
                except Exception as e:
                    return kind, -1, f"{type(e).__name__}", time.time() - t0

        results = await asyncio.gather(*[get(k) for k in resources])
        return context, results


async def main():
    resources = ["pods", "ns", "svc", "cm"]

    print("=" * 70)
    print("场景 1：单集群内多资源并发")
    print("=" * 70)
    sem = asyncio.Semaphore(10)
    ctx, results = await scan_cluster("kind-k8s-c1", resources, sem)
    print(f"  集群 {ctx}:")
    for kind, n, err, el in results:
        flag = f"错误 {err}" if err else f"{n} 个"
        print(f"    {kind:<5}: {flag:<12} ({el*1000:.0f}ms)")

    print()
    print("=" * 70)
    print("场景 2：多集群并发（每集群独立 client）")
    print("=" * 70)
    t0 = time.time()
    all_results = await asyncio.gather(
        *[scan_cluster(c, resources, sem) for c in CONTEXTS]
    )
    t_concurrent = time.time() - t0
    for ctx, results in all_results:
        total = sum(n for _, n, _, _ in results)
        print(f"  集群 {ctx}: 合计 {total} 个资源")
    print(f"  并发总耗时: {t_concurrent:.3f}s")

    print()
    print("=" * 70)
    print("场景 3：串行 vs 并发（多集群）")
    print("=" * 70)
    t0 = time.time()
    for c in CONTEXTS:
        await scan_cluster(c, resources, sem)
    t_serial = time.time() - t0
    print(f"  串行总耗时: {t_serial:.3f}s")
    print(f"  并发总耗时: {t_concurrent:.3f}s")
    print(f"  >>> 加速 {t_serial/t_concurrent:.2f}x")

    print()
    print("=" * 70)
    print("场景 4：信号量限流效果（限 vs 不限）")
    print("=" * 70)
    for lim in (1, 2, 5, 20):
        s = asyncio.Semaphore(lim)
        t0 = time.time()
        await asyncio.gather(*[scan_cluster(c, resources, s) for c in CONTEXTS])
        el = time.time() - t0
        print(f"  信号量={lim:<3}: {el:.3f}s")

    print()
    print("=" * 70)
    print("场景 5：并发下的失败形态 —— gather 不隔离异常")
    print("=" * 70)
    print("  gather 默认 return_exceptions=False：一个失败全部炸")
    try:
        await asyncio.gather(
            scan_cluster("kind-k8s-c1", ["pods"], sem),
            scan_cluster("不存在的集群-xxx", ["pods"], sem),
        )
    except Exception as e:
        print(f"    抛异常: {type(e).__name__}: {str(e)[:90]}")
        print(f"    -> kind-k8s-c1 的结果被丢弃（即使它成功了）")

    print("\n  加 return_exceptions=True：")
    rs = await asyncio.gather(
        scan_cluster("kind-k8s-c1", ["pods"], sem),
        scan_cluster("不存在的集群-xxx", ["pods"], sem),
        return_exceptions=True,
    )
    for i, r in enumerate(rs):
        if isinstance(r, Exception):
            print(f"    [{i}] 失败: {type(r).__name__}: {str(r)[:60]}")
        else:
            print(f"    [{i}] 成功: {r[0]}")


asyncio.run(main())
