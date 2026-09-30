"""课 9 收尾：异步 watch + 什么时候不该用异步

1. 异步 watch 的形态（课 6 的 watch 在异步下怎么写）
2. 并发下 409 冲突（课 5 的知识点在异步下重演 —— 比同步更容易触发）
3. 什么时候不该用异步（用实测数据说话）
"""
import asyncio
import time

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

NS = "py-lesson09"


async def setup(v1):
    try:
        await v1.create_namespace(body={"metadata": {"name": NS}})
    except Exception:
        pass


async def cleanup(v1):
    try:
        await v1.delete_namespace(name=NS)
        print(f"  已清理 ns {NS}")
    except Exception as e:
        print(f"  清理: {type(e).__name__}")


async def demo_async_watch(v1):
    print("=" * 70)
    print("1. 异步 watch 形态")
    print("=" * 70)
    w = ka.watch.Watch()

    # 后台制造事件
    async def maker():
        await asyncio.sleep(0.5)
        for i in range(3):
            try:
                await v1.create_namespaced_config_map(
                    namespace=NS,
                    body={"metadata": {"name": f"w-{i}"}, "data": {"i": str(i)}})
            except Exception:
                pass
            await asyncio.sleep(0.2)

    task = asyncio.create_task(maker())

    seen = []
    t0 = time.time()
    async with w:
        async for event in w.stream(v1.list_namespaced_config_map,
                                    namespace=NS, timeout_seconds=4):
            seen.append((event["type"], event["object"].metadata.name))
            if len(seen) >= 3:
                break
    el = time.time() - t0
    await task

    print(f"  收到 {len(seen)} 个事件 (耗时 {el:.2f}s):")
    for t, n in seen:
        print(f"    {t:<8} {n}")
    print("  -> 异步 watch 用 `async with w` + `async for event in w.stream(...)`")
    print("     比同步多两个 async 关键字，其余同名")


async def demo_concurrent_409(v1):
    print()
    print("=" * 70)
    print("2. 并发下的 409 冲突（课 5 在异步下重演）")
    print("=" * 70)
    name = "conflict-cm"
    try:
        await v1.create_namespaced_config_map(
            namespace=NS, body={"metadata": {"name": name}, "data": {"v": "1"}})
        print(f"  创建 {name} 成功")
    except Exception as e:
        print(f"  创建: {type(e).__name__}")

    # 10 个并发 create 同名资源
    async def try_create(i):
        try:
            await v1.create_namespaced_config_map(
                namespace=NS, body={"metadata": {"name": name}, "data": {"v": str(i)}})
            return "OK"
        except Exception as e:
            return f"{type(e).__name__}"

    results = await asyncio.gather(*[try_create(i) for i in range(10)])
    from collections import Counter
    c = Counter(results)
    print(f"  10 个并发 create 同名资源: {dict(c)}")
    print("  -> 异步让并发更容易写出来，也让 409 更容易撞上")
    print("     异步不解决冲突，反而放大冲突（课 5 的'重读→重放→再写'依然要写）")


async def demo_when_not_async(v1):
    print()
    print("=" * 70)
    print("3. 什么时候不该用异步 —— 实测三类负载")
    print("=" * 70)

    N = 40

    # (a) 少量大请求：反序列化主导
    print("\n  (a) 少量大请求（反序列化主导）")
    t0 = time.time()
    for _ in range(N):
        await v1.list_config_map_for_all_namespaces()
    t_s = time.time() - t0
    t0 = time.time()
    await asyncio.gather(*[v1.list_config_map_for_all_namespaces() for _ in range(N)])
    t_c = time.time() - t0
    print(f"      串行 {t_s:.3f}s / 并发 {t_c:.3f}s -> {t_s/t_c:.2f}x  (收益低)")

    # (b) 大量小请求：IO 主导
    print("\n  (b) 大量小请求（单个 read，响应极小）")
    try:
        await v1.create_namespaced_config_map(
            namespace=NS, body={"metadata": {"name": "tiny"}, "data": {"a": "1"}})
    except Exception:
        pass

    async def read_one():
        return await v1.read_namespaced_config_map(name="tiny", namespace=NS)

    t0 = time.time()
    for _ in range(N):
        await read_one()
    t_s = time.time() - t0
    t0 = time.time()
    await asyncio.gather(*[read_one() for _ in range(N)])
    t_c = time.time() - t0
    print(f"      串行 {t_s:.3f}s / 并发 {t_c:.3f}s -> {t_s/t_c:.2f}x  (收益高)")

    # (c) CPU 密集（纯本地计算，无任何 IO）
    print("\n  (c) 纯 CPU 计算（无 IO）")

    def cpu_work():
        s = 0
        for i in range(30000):
            s += i * i
        return s

    t0 = time.time()
    for _ in range(N):
        cpu_work()
    t_s = time.time() - t0

    async def cpu_async():
        return cpu_work()

    t0 = time.time()
    await asyncio.gather(*[cpu_async() for _ in range(N)])
    t_c = time.time() - t0
    print(f"      串行 {t_s:.3f}s / 并发 {t_c:.3f}s -> {t_s/t_c:.2f}x  (无收益)")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        await setup(v1)
        await demo_async_watch(v1)
        await demo_concurrent_409(v1)
        await demo_when_not_async(v1)
        await cleanup(v1)


asyncio.run(main())
