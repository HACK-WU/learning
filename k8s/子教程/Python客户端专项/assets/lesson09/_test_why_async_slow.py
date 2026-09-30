"""决定性实验：异步为什么只有 1.2x？

两个竞争假设：
  H_A: 瓶颈是反序列化（CPU 密集，跑在事件循环单线程上）→ 异步无解
       预测：raw(不反序列化) 的 gather 加速比 >> 完整反序列化的加速比
  H_B: 瓶颈是 apiserver 侧限流/排队 → 加并发也没用
       预测：raw 的 gather 加速比同样很低

方法：同一批请求，分别测
  - _preload_content=False（只拿 HTTP 响应体，不反序列化）
  - 完整反序列化
对比两者的 gather 加速比
"""
import asyncio
import time

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

NS = "py-lesson09-bench"
N = 60


async def create_data(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass
    sem = asyncio.Semaphore(30)
    async def mk(i):
        async with sem:
            try:
                await v1.create_namespaced_config_map(
                    namespace=NS,
                    body={"metadata": {"name": f"cm-{i:03d}"},
                          "data": {"k": "v" * 500, "idx": str(i)}})
            except Exception:
                pass
    await asyncio.gather(*[mk(i) for i in range(200)])
    r = await v1.list_namespaced_config_map(namespace=NS)
    print(f"  数据就绪: {len(r.items)} 个 ConfigMap")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await create_data(v1)
        print()

        print("=" * 70)
        print("A 组：完整反序列化（默认）")
        print("=" * 70)
        t0 = time.time()
        await v1.list_namespaced_config_map(namespace=NS)
        one_full = time.time() - t0
        print(f"  单个请求: {one_full*1000:.1f}ms")

        t0 = time.time()
        for _ in range(N):
            await v1.list_namespaced_config_map(namespace=NS)
        t_full_serial = time.time() - t0
        print(f"  串行 x{N}: {t_full_serial:.3f}s")

        t0 = time.time()
        await asyncio.gather(*[v1.list_namespaced_config_map(namespace=NS)
                               for _ in range(N)])
        t_full_gather = time.time() - t0
        print(f"  gather x{N}: {t_full_gather:.3f}s")
        print(f"  >>> 加速比: {t_full_serial/t_full_gather:.2f}x")

        print()
        print("=" * 70)
        print("B 组：_preload_content=False（不反序列化，只拿 HTTP 响应）")
        print("=" * 70)

        async def one_raw():
            r = await v1.list_namespaced_config_map(namespace=NS,
                                                    _preload_content=False)
            data = await r.read()
            return len(data)

        t0 = time.time()
        size = await one_raw()
        one_raw_t = time.time() - t0
        print(f"  单个请求: {one_raw_t*1000:.1f}ms  (响应体 {size} 字节)")

        t0 = time.time()
        for _ in range(N):
            await one_raw()
        t_raw_serial = time.time() - t0
        print(f"  串行 x{N}: {t_raw_serial:.3f}s")

        t0 = time.time()
        await asyncio.gather(*[one_raw() for _ in range(N)])
        t_raw_gather = time.time() - t0
        print(f"  gather x{N}: {t_raw_gather:.3f}s")
        print(f"  >>> 加速比: {t_raw_serial/t_raw_gather:.2f}x")

        print()
        print("=" * 70)
        print("结论判定")
        print("=" * 70)
        print(f"  完整反序列化 单请求 {one_full*1000:.1f}ms 中，")
        print(f"  HTTP 部分只占 {one_raw_t*1000:.1f}ms "
              f"({one_raw_t/one_full*100:.0f}%)，")
        print(f"  反序列化占 {(one_full-one_raw_t)*1000:.1f}ms "
              f"({(1-one_raw_t/one_full)*100:.0f}%)")
        print()
        print(f"  纯 HTTP 的并发加速比: {t_raw_serial/t_raw_gather:.2f}x  "
              f"<-- 异步对 IO 有效")
        print(f"  含反序列化的加速比  : {t_full_serial/t_full_gather:.2f}x  "
              f"<-- 被 CPU 拖回")
        print()
        if t_raw_serial / t_raw_gather > t_full_serial / t_full_gather * 2:
            print("  => 假设 H_A 成立：瓶颈是 CPU 反序列化，异步救不了 CPU")
            print("     （反序列化跑在事件循环单线程上，天然串行）")
        else:
            print("  => 假设 H_B 更可能：瓶颈在服务端/IO 层")

        # 清理
        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"\n  清理失败: {type(e).__name__}")


asyncio.run(main())
