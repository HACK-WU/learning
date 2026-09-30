"""验证 3：异步版相对同步版的两项独有收益 + 优雅退出

收益 1：单个事件循环里同时 watch 多种资源（同步版要开 N 个线程）
收益 2：调谐 IO 并发（多 worker 同时 patch）
验证 3：优雅退出 —— 只 set(stop) 够不够？
"""
import asyncio
import sys
import time

sys.path.insert(0, "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/assets/lesson06-async")

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api

from async_controller import AsyncInformer, AsyncWorkQueueFixed

NS = "py-lesson06-adv"
T0 = time.time()


def log(msg):
    print(f"  [{time.time()-T0:5.2f}s] {msg}")


async def main():
    await ka.config.load_kube_config()
    async with ApiClient() as api:
        v1 = CoreV1Api(api)
        try:
            await v1.create_namespace(body={"metadata": {"name": NS}})
        except Exception:
            pass
        await asyncio.sleep(0.5)

        print("=" * 70)
        print("收益 1：一个事件循环，同时 watch 多种资源")
        print("=" * 70)

        q_cm = AsyncWorkQueueFixed()
        q_secret = AsyncWorkQueueFixed()

        inf_cm = AsyncInformer(v1.list_namespaced_config_map, NS, q_cm)
        inf_secret = AsyncInformer(v1.list_namespaced_secret, NS, q_secret)

        stop = asyncio.Event()
        tasks = [
            asyncio.create_task(inf_cm.run(stop)),
            asyncio.create_task(inf_secret.run(stop)),
        ]
        log("两个 informer 已启动（同一事件循环，零线程）")
        await asyncio.sleep(0.8)

        # 同时往两种资源写
        for i in range(2):
            await v1.create_namespaced_config_map(
                namespace=NS,
                body={"metadata": {"name": f"cm-{i}"}, "data": {"a": "1"}})
        await v1.create_namespaced_secret(
            namespace=NS,
            body={"metadata": {"name": "sec-0"}, "data": {}})

        await asyncio.sleep(2.0)

        print(f"\n  ConfigMap informer: {len(inf_cm.events)} 事件 "
              f"cache={len(inf_cm.cache)}")
        for et, n in inf_cm.events:
            print(f"      {et:<9} {n}")
        print(f"  Secret informer:    {len(inf_secret.events)} 事件 "
              f"cache={len(inf_secret.cache)}")
        for et, n in inf_secret.events:
            print(f"      {et:<9} {n}")

        print("\n  -> 两种资源互不干扰，各自的 rv 独立推进")
        print(f"     cm.rv={inf_cm.rv}  secret.rv={inf_secret.rv}")

        # 停止
        stop.set()
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        log("两个 informer 已停止")

        print()
        print("=" * 70)
        print("验证：优雅退出 —— 只 set(stop) 够不够？")
        print("=" * 70)

        stop2 = asyncio.Event()
        q3 = AsyncWorkQueueFixed()
        inf3 = AsyncInformer(v1.list_namespaced_config_map, NS, q3)
        t3 = asyncio.create_task(inf3.run(stop2))
        await asyncio.sleep(1.0)

        log("只调用 stop.set()，不 cancel")
        stop2.set()
        try:
            await asyncio.wait_for(t3, timeout=3.0)
            log("  -> 任务自己结束了")
        except asyncio.TimeoutError:
            log("  -> ✗ 3 秒后任务仍在运行！stop.set() 不足以唤醒它")
            log("     原因：watch 卡在 await 网络读上，不检查 stop 标志")
            t3.cancel()
            await asyncio.gather(t3, return_exceptions=True)
            log("     必须 cancel() 才能退出")

        print()
        print("=" * 70)
        print("收益 2：调谐 IO 并发（多 worker 同时 patch）")
        print("=" * 70)
        print("  课 9 实测：IO 部分并发可到 4~6x")
        print("  调谐 = read(IO) + patch(IO)，正适合并发")

        try:
            await v1.delete_namespace(name=NS)
            print(f"\n  已清理 ns {NS}")
        except Exception as e:
            print(f"  清理: {type(e).__name__}")


asyncio.run(main())
