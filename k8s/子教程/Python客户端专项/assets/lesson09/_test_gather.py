"""课 9 核心：asyncio.gather 并发到底快多少 + 信号量限流

对标前面同步实测（N=60 全量 list pods）：
  串行          0.98s
  async_req 2线程 1.09s   （最快，也就这样了）
  async_req 16线程 3.33s  （加线程反而更慢）

现在看异步能到多少。
"""
import asyncio
import time

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

N = 60


async def bench_gather(v1, n, sem=None, tag=""):
    async def one():
        if sem:
            async with sem:
                return await v1.list_pod_for_all_namespaces()
        return await v1.list_pod_for_all_namespaces()

    t0 = time.time()
    results = await asyncio.gather(*[one() for _ in range(n)])
    el = time.time() - t0
    print(f"  {tag}: {el:.3f}s  (返回 {len(results)} 个, pods={len(results[0].items)})")
    return el


async def bench_serial(v1, n, tag=""):
    t0 = time.time()
    cnt = 0
    for _ in range(n):
        r = await v1.list_pod_for_all_namespaces()
        cnt = len(r.items)
    el = time.time() - t0
    print(f"  {tag}: {el:.3f}s  (pods={cnt})")
    return el


async def main():
    await ka.config.load_kube_config()

    async with ApiClient() as api:
        v1 = CoreV1Api(api)

        print("=" * 64)
        print(f"N={N} 全量 list pods")
        print("=" * 64)

        # 预热
        await v1.list_pod_for_all_namespaces()
        print("\n[预热完成]\n")

        t_serial = await bench_serial(v1, N, "串行 await x60      ")

        print()
        for lim in (5, 10, 20, 50):
            sem = asyncio.Semaphore(lim)
            await bench_gather(v1, N, sem, f"gather 信号量={lim:<3}    ")

        print()
        t_no_sem = await bench_gather(v1, N, None, "gather 无限流        ")

        print()
        print("=" * 64)
        print(f"串行 await     : {t_serial:.3f}s")
        print(f"gather 无限流  : {t_no_sem:.3f}s  -> 加速 {t_serial/t_no_sem:.1f}x")
        print("=" * 64)

        # 再跑一次无限流，看稳定性
        print("\n稳定性复测（gather 无限流 x3）：")
        for i in range(3):
            await bench_gather(v1, N, None, f"  第{i+1}次")


asyncio.run(main())
