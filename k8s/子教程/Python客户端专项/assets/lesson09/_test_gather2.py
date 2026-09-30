"""放大样本重测：gather 加速比

上一轮只有 1.4x，怀疑是样本太小（10 pods，单请求 9.5ms）。
本轮：
  1. 造一个大的响应体（批量建 ConfigMap，list 出来很大）
  2. 用节点数多 / 资源多的集群（otel-l11: 23 pods / 8 ns）
  3. 对比：同步 async_req(2线程) vs 异步 gather

目标：让单请求耗时长到能体现并发收益
"""
import asyncio
import time

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

N = 60
NS = "py-lesson09-bench"


async def create_bulk():
    """建 200 个 ConfigMap，让 list 响应变大"""
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        # 建 ns
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
            print(f"  创建 ns {NS}")
        except Exception as e:
            print(f"  ns 已存在或失败: {type(e).__name__}")

        body = {"metadata": {}, "data": {"k": "v" * 500}}
        ok = 0
        sem = asyncio.Semaphore(20)
        tasks = []
        for i in range(200):
            cm = {"metadata": {"name": f"cm-{i:03d}"},
                  "data": {"k": "v" * 500, "idx": str(i)}}
            tasks.append(_create_one(v1, cm, sem))
        results = await asyncio.gather(*tasks, return_exceptions=True)
        ok = sum(1 for r in results if not isinstance(r, Exception))
        print(f"  创建 ConfigMap: {ok}/200")
        return ok


async def _create_one(v1, cm, sem):
    async with sem:
        try:
            return await v1.create_namespaced_config_map(namespace=NS, body=cm)
        except Exception:
            return None


async def bench():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)

        # 单请求基准
        t0 = time.time()
        r = await v1.list_namespaced_config_map(namespace=NS)
        one = time.time() - t0
        print(f"  单个 list configmap: {one*1000:.1f}ms  (拿到 {len(r.items)} 个)")
        print(f"  若串行 N={N} 应≈{one*N:.2f}s\n")

        # 串行
        t0 = time.time()
        for _ in range(N):
            await v1.list_namespaced_config_map(namespace=NS)
        t_serial = time.time() - t0
        print(f"  串行 await x{N}: {t_serial:.3f}s")

        # gather
        for lim in (5, 10, 20, 50):
            sem = asyncio.Semaphore(lim)

            async def one_cm():
                async with sem:
                    return await v1.list_namespaced_config_map(namespace=NS)

            t0 = time.time()
            await asyncio.gather(*[one_cm() for _ in range(N)])
            el = time.time() - t0
            print(f"  gather 信号量={lim:<3}: {el:.3f}s  加速 {t_serial/el:.1f}x")

        t0 = time.time()
        await asyncio.gather(*[v1.list_namespaced_config_map(namespace=NS)
                               for _ in range(N)])
        t_nosem = time.time() - t0
        print(f"  gather 无限流    : {t_nosem:.3f}s  加速 {t_serial/t_nosem:.1f}x")


async def cleanup():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.delete_namespace(name=NS)
            print(f"  已删除 ns {NS}")
        except Exception as e:
            print(f"  删除失败: {type(e).__name__}: {e}")


async def main():
    print("=" * 64)
    print("准备大响应体测试数据")
    print("=" * 64)
    await create_bulk()
    print()
    print("=" * 64)
    print("并发度对比")
    print("=" * 64)
    await bench()
    print()
    print("=" * 64)
    print("清理")
    print("=" * 64)
    await cleanup()


asyncio.run(main())
